FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .

ARG VERSION=dev
ARG BUILD_TIME=unknown

RUN go test ./...
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-X main.version=${VERSION} -X main.buildTime=${BUILD_TIME}" \
    -o backend .

FROM scratch
COPY --from=builder /app/backend /backend
EXPOSE 8080
ENTRYPOINT ["/backend"]
