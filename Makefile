.PHONY: image

IMAGE_NAME=mortbauer/discourse
IMAGE_TAG:=latest
BUILD_ARGS:= --build-arg REVISION="$(shell git rev-parse HEAD)" --build-arg BUILDTIME="$(shell date --rfc-3339=seconds)"

image:
	docker buildx build --tag ${IMAGE_NAME}:${IMAGE_TAG} --progress=plain ${BUILD_ARGS} --platform linux/arm64,linux/amd64 .
