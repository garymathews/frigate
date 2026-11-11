variable "BUILD_JOBS" {
  default = "4"
}

// A published artifact image can replace the local build using docker-image://.
variable "ROCM_ARTIFACTS" {
  default = "target:rocm-artifacts"
}

target "rocm-artifacts" {
  dockerfile = "docker/rocm/Dockerfile.artifacts"
  platforms  = ["linux/amd64"]
  target     = "artifacts"
  args       = {
    BUILD_JOBS = BUILD_JOBS
  }
}

target "deps" {
  dockerfile = "docker/main/Dockerfile"
  platforms  = ["linux/amd64"]
  target     = "deps"
}

target "rootfs" {
  dockerfile = "docker/main/Dockerfile"
  platforms  = ["linux/amd64"]
  target     = "rootfs"
}

target "rocm" {
  dockerfile = "docker/rocm/Dockerfile"
  platforms  = ["linux/amd64"]
  target     = "rocm-deps"
  contexts   = {
    deps           = "target:deps",
    rocm-artifacts = ROCM_ARTIFACTS,
    rootfs         = "target:rootfs"
  }
}
