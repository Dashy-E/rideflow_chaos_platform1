# ---- builder ----
FROM golang:1.27-alpine AS builder
WORKDIR /build
COPY go.mod main.go ./
RUN go mod tidy
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /api-gateway .

# ---- runtime ----
FROM gcr.io/distroless/static-debian12
COPY --from=builder /api-gateway /api-gateway
USER 10001
EXPOSE 8080
ENTRYPOINT ["/api-gateway"]
