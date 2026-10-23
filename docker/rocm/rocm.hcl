variable "ROCM" {
  default = "10.1.0a20260910"
}
variable "ROCM_SHA256" {
  default = "6765f5e4fadf39a84994b0a6581d0ef4ee11be24942f15fc9039a8e83ca992fa"
}
variable "BUILD_JOBS" {
  default = "4"
}
// A published artifact image can replace the local build using docker-image://.
variable "ROCM_ARTIFACTS" {
  default = "target:rocm-artifacts"
}
variable "HSA_OVERRIDE_GFX_VERSION" {
  default = ""
}
variable "HSA_OVERRIDE" {
  default = "0"
}

target rocm-artifacts {
  dockerfile = "docker/rocm/Dockerfile"
  platforms = ["linux/amd64"]
  target = "artifacts"
  args = {
    ROCM = ROCM,
    ROCM_SHA256 = ROCM_SHA256,
    BUILD_JOBS = BUILD_JOBS,
    // MIGraphX rocm-10.1 and ONNX Runtime v1.31.0.
    MIGRAPHX_REF = "95672916ed289d4be9d230a9be732e1bbad97e8c",
    ONNXRUNTIME_REF = "402979ac1bef89dcd55add41eaa7277c407599eb"
  }
}

target deps {
  dockerfile = "docker/main/Dockerfile"
  platforms = ["linux/amd64"]
  target = "deps"
}

target rootfs {
  dockerfile = "docker/main/Dockerfile"
  platforms = ["linux/amd64"]
  target = "rootfs"
}

target rocm {
  dockerfile = "docker/rocm/Dockerfile"
  target = "rocm-deps"
  contexts = {
    deps = "target:deps",
    rocm-artifacts = ROCM_ARTIFACTS,
    rootfs = "target:rootfs"
  }
  platforms = ["linux/amd64"]
  args = {
    HSA_OVERRIDE_GFX_VERSION = HSA_OVERRIDE_GFX_VERSION,
    HSA_OVERRIDE = HSA_OVERRIDE
  }
}
