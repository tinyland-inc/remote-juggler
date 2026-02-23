FROM golang:1.23-alpine AS builder

WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -o /campaign-runner .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY --from=builder /campaign-runner /usr/local/bin/campaign-runner
ENTRYPOINT ["campaign-runner"]
