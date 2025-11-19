FROM rust:1.91.1-trixie as builder
WORKDIR /usr/src/grestless
COPY src/ src/
COPY Cargo.toml .
COPY Cargo.lock .
RUN cargo install --path .

FROM debian:trixie-slim
COPY --from=builder /usr/local/cargo/bin/grestless /usr/local/bin/grestless
CMD ["grestless"]
