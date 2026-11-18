# Produção (PC de casa): compila o app Flutter para web e serve com nginx.
FROM ghcr.io/cirruslabs/flutter:3.38.5 AS build
ARG API_URL
ENV PUB_CACHE=/pub-cache
RUN flutter config --no-analytics --enable-web
WORKDIR /app
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get
COPY app/ ./
RUN flutter build web --release --dart-define=API_URL="${API_URL}" --no-wasm-dry-run --pwa-strategy=none

FROM nginx:1.27-alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
