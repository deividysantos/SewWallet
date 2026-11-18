# Flutter SDK (inclui Android SDK, usado depois para gerar o APK).
FROM ghcr.io/cirruslabs/flutter:3.38.5

# Cache de pacotes num caminho próprio (vira volume no compose).
ENV PUB_CACHE=/pub-cache
ENV PATH="$PATH:/pub-cache/bin"

RUN flutter config --no-analytics --enable-web \
  && flutter precache --web \
  && dart pub global activate dhttpd
WORKDIR /app

EXPOSE 8080
CMD ["sh", "/docker/app-dev.sh"]
