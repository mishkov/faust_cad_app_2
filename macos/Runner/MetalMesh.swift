import FlutterMacOS
import MetalKit

struct MetalFailure: Error, CustomStringConvertible {
  let description: String
  init(_ message: String) { description = message }
}

func typedArray<T>(_ value: Any?, _: T.Type) throws -> [T] {
  guard let data = (value as? FlutterStandardTypedData)?.data,
    data.count % MemoryLayout<T>.stride == 0, data.count <= 64 * 1024 * 1024
  else {
    throw MetalFailure(
      "Invalid or oversized Metal typed packet: \(String(describing: type(of:value))) stride \(MemoryLayout<T>.stride)"
    )
  }
  return data.withUnsafeBytes { raw in
    // StandardMessageCodec does not promise alignment for typed data.
    (0..<(raw.count / MemoryLayout<T>.stride)).map {
      raw.loadUnaligned(fromByteOffset: $0 * MemoryLayout<T>.stride, as: T.self)
    }
  }
}

final class MetalMesh {
  let vertices: MTLBuffer?, indices: MTLBuffer?, lines: MTLBuffer?
  let indexCount: Int, lineCount: Int, faceCount: Int, bytes: Int
  let source: [Double], indexArray: [UInt32], vertexArray: [Float], plane: [Double]?
  let minimum: SIMD3<Double>, maximum: SIMD3<Double>

  init(_ packet: [String: Any], device: MTLDevice) throws {
    vertexArray = try typedArray(packet["vertices"], Float.self)
    source = try typedArray(packet["source"], Double.self)
    indexArray = try typedArray(packet["indices"], UInt32.self)
    let lineArray = try typedArray(packet["lines"], Float.self)
    faceCount = (packet["faceCount"] as? NSNumber)?.intValue ?? 0
    let vertexCount = vertexArray.count / 12
    guard vertexArray.count % 12 == 0, source.count == vertexArray.count / 2,
      lineArray.count % 90 == 0, indexArray.count % 3 == 0,
      indexArray.allSatisfy({ Int($0) < vertexCount }),
      vertexArray.allSatisfy({ $0.isFinite }), source.allSatisfy({ $0.isFinite }),
      lineArray.allSatisfy({ $0.isFinite }), faceCount >= 0, faceCount <= 100000
    else {
      throw MetalFailure("Invalid Metal mesh layout")
    }
    for i in stride(from: 0, to: vertexArray.count, by: 12) {
      guard
        vertexArray[i + 10] == -1
          || (vertexArray[i + 10] >= 0 && vertexArray[i + 10] < Float(faceCount))
      else {
        throw MetalFailure("Invalid Metal face index")
      }
    }
    plane = packet["plane"] == nil ? nil : try typedArray(packet["plane"], Double.self)
    if let p = plane, p.count != 7 || !p.allSatisfy({ $0.isFinite }) {
      throw MetalFailure("Invalid sketch plane")
    }
    func buffer<T>(_ array: [T]) throws -> MTLBuffer? {
      if array.isEmpty { return nil }
      guard
        let result = array.withUnsafeBytes({
          device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        })
      else {
        throw MetalFailure("Metal could not allocate geometry")
      }
      return result
    }
    vertices = try buffer(vertexArray)
    indices = try buffer(indexArray)
    lines = try buffer(lineArray)
    indexCount = indexArray.count
    lineCount = lineArray.count / 15
    bytes = vertexArray.count * 4 + indexArray.count * 4 + lineArray.count * 4
    var low = SIMD3<Double>(repeating: .infinity)
    var high = SIMD3<Double>(repeating: -.infinity)
    for i in stride(from: 0, to: source.count, by: 6) {
      let p = SIMD3(source[i], source[i + 1], source[i + 2])
      low = simd_min(low, p)
      high = simd_max(high, p)
    }
    for i in stride(from: 0, to: lineArray.count, by: 90) {
      for offset in [0, 6] {
        let p = SIMD3(
          Double(lineArray[i + offset]) + Double(lineArray[i + offset + 3]),
          Double(lineArray[i + offset + 1]) + Double(lineArray[i + offset + 4]),
          Double(lineArray[i + offset + 2]) + Double(lineArray[i + offset + 5]))
        low = simd_min(low, p)
        high = simd_max(high, p)
      }
    }
    minimum = low
    maximum = high
  }

  func visible(_ camera: MetalCamera) -> Bool {
    guard let p = plane else { return true }
    return abs(simd_dot(camera.eye - SIMD3(p[0], p[1], p[2]), SIMD3(p[3], p[4], p[5]))) > p[6]
  }

  func needsPreciseClip(_ camera: MetalCamera) -> Bool {
    if indexCount == 0 { return false }
    if camera.orthographicDistance > 0 { return false }
    return minimumDepth(camera) < max(0.001, simd_length(maximum - minimum) * 1e-6)
  }

  func minimumDepth(_ camera: MetalCamera) -> Double {
    var depth = Double.infinity
    for x in [minimum.x, maximum.x] {
      for y in [minimum.y, maximum.y] {
        for z in [minimum.z, maximum.z] {
          depth = min(depth, camera.transform(SIMD3(x, y, z)).y)
        }
      }
    }
    return depth
  }

  func maximumDepth(_ camera: MetalCamera) -> Double {
    var depth = -Double.infinity
    for x in [minimum.x, maximum.x] {
      for y in [minimum.y, maximum.y] {
        for z in [minimum.z, maximum.z] {
          depth = max(depth, camera.transform(SIMD3(x, y, z)).y)
        }
      }
    }
    return depth
  }

  // Only near/inside views use double-precision preprocessing. Rasterization,
  // lighting, edge occlusion and presentation always remain on Metal.
  func clipped(_ camera: MetalCamera) -> [Float] {
    typealias V = (p: SIMD3<Double>, n: SIMD3<Double>)
    let planes = [
      SIMD3(0.0, 1, 0), SIMD3(1, camera.width / (2 * camera.focal), 0),
      SIMD3(-1, camera.width / (2 * camera.focal), 0),
      SIMD3(0, camera.height / (2 * camera.focal), 1),
      SIMD3(0, camera.height / (2 * camera.focal), -1),
    ]
    var output = [Float]()
    output.reserveCapacity(indexCount * 12)
    for t in stride(from: 0, to: indexCount, by: 3) {
      var polygon: [V] = (0..<3).map {
        let i = Int(indexArray[t + $0]) * 6
        return (
          camera.transform(SIMD3(source[i], source[i + 1], source[i + 2])),
          SIMD3(source[i + 3], source[i + 4], source[i + 5])
        )
      }
      let i = Int(indexArray[t]) * 6
      let facing: Float =
        simd_dot(polygon[0].n, SIMD3(source[i], source[i + 1], source[i + 2]) - camera.eye) > 0
        ? -1 : 1
      let face = vertexArray[Int(indexArray[t]) * 12 + 10]
      for (j, plane) in planes.enumerated() {
        if polygon.isEmpty { break }
        var next = [V]()
        var previous = polygon.last!
        func distance(_ v: V) -> Double { simd_dot(plane, v.p) - (j == 0 ? 1e-6 : 0) }
        var previousDistance = distance(previous)
        for current in polygon {
          let d = distance(current)
          if (d >= 0) != (previousDistance >= 0) {
            let f = previousDistance / (previousDistance - d)
            next.append(
              (previous.p + (current.p - previous.p) * f, previous.n + (current.n - previous.n) * f)
            )
          }
          if d >= 0 { next.append(current) }
          previous = current
          previousDistance = d
        }
        polygon = next
      }
      if polygon.count < 3 { continue }
      for j in 1..<(polygon.count - 1) {
        for v in [polygon[0], polygon[j], polygon[j + 1]] {
          output.append(contentsOf: [
            Float(v.p.x), Float(v.p.y), Float(v.p.z), 0, 0, 0, Float(v.n.x), Float(v.n.y),
            Float(v.n.z), 0, face, facing,
          ])
        }
      }
    }
    return output
  }
}

struct MetalCamera {
  let eye: SIMD3<Double>, yaw: Double, pitch: Double, focal: Double, width: Double, height: Double,
    dpr: Double, orthographicDistance: Double
  init(_ data: Any?) throws {
    let p = try typedArray(data, Double.self)
    guard (p.count == 9 || p.count == 10), p.allSatisfy({ $0.isFinite }), p[5] > 0, p[6] > 0, p[7] > 0, p[8] > 0,
      p[6] * p[8] <= 16384, p[7] * p[8] <= 16384, p[6] * p[7] * p[8] * p[8] <= 32_000_000
    else { throw MetalFailure("Invalid Metal camera or drawable size") }
    orthographicDistance = p.count == 10 ? p[9] : 0
    guard orthographicDistance >= 0 else { throw MetalFailure("Invalid projection scale") }
    eye = SIMD3(p[0], p[1], p[2])
    yaw = p[3]
    pitch = p[4]
    focal = p[5]
    width = p[6]
    height = p[7]
    dpr = p[8]
  }
  func transform(_ position: SIMD3<Double>) -> SIMD3<Double> {
    let p = position - eye
    let cy = cos(-yaw)
    let sy = sin(-yaw)
    let cp = cos(-pitch)
    let sp = sin(-pitch)
    let x = p.x * cy - p.y * sy
    let y = p.x * sy + p.y * cy
    return SIMD3(x, y * cp - p.z * sp, y * sp + p.z * cp)
  }
  func uniforms(precise: Bool, wireframe: Bool, depthScale: Float) -> [SIMD4<Float>] {
    let high = SIMD3<Float>(eye)
    let low = eye - SIMD3<Double>(high)
    return [
      SIMD4(high, 0), SIMD4(SIMD3<Float>(low), 0),
      SIMD4(Float(cos(-yaw)), Float(sin(-yaw)), Float(cos(-pitch)), Float(sin(-pitch))),
      SIMD4(Float(width), Float(height), Float(focal), Float(dpr)),
      SIMD4(precise ? 1 : 0, depthScale, wireframe ? 1 : 0, Float(orthographicDistance)),
    ]
  }
}
