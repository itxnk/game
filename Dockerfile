FROM debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.47.5

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git unzip xz-utils ca-certificates bash libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN curl -L "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o flutter.tar.xz \
    && tar -xf flutter.tar.xz \
    && rm flutter.tar.xz

ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Flutter SDK is extracted as root; explicitly trust its Git directory.
RUN git config --global --add safe.directory /opt/flutter

RUN flutter --version

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

RUN flutter build web --release

FROM nginx:alpine

RUN rm -rf /usr/share/nginx/html/*

COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
