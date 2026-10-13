# ---- builder ----
FROM golang:1.27-alpine AS builder
WORKDIR /build
COPY go.mod main.go ./
RUN go mod tidy
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /driver-service .

# ---- runtime ----
FROM gcr.io/distroless/static-debian12
COPY --from=builder /driver-service /driver-service
USER 10001
EXPOSE 8083
ENTRYPOINT ["/driver-service"]
