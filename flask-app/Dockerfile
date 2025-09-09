FROM python:3.9-slim

# 보안/재현성: 빌드 아규먼트로 앱 버전 전달
ARG APP_VERSION=v1.0

RUN apt-get update && apt-get install -y --no-install-recommends curl \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 의존성 먼저 설치 (빌드 캐시 최적화)
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && useradd -m appuser

COPY . .

# 비루트 사용자 추가 (보안 강화)
USER appuser

ENV APP_VERSION=${APP_VERSION}
ENV PYTHONUNBUFFERED=1

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "30", "app:app"]


# FROM python:3.12-slim

# # 보안/재현성에 유리한 기본 설정
# ENV PYTHONUNBUFFERED=1 \
#     PORT=5000 \
#     GUNICORN_WORKERS=2 \
#     GUNICORN_TIMEOUT=30

# WORKDIR /app

# # 의존성 먼저 설치 (빌드 캐시 최적화)
# COPY requirements.txt .
# RUN pip install --upgrade pip \
#  && pip install --no-cache-dir -r requirements.txt \
#  && useradd -m appuser

# # 소스 복사
# COPY . .

# # 컨테이너 내부 헬스체크(옵션)
# # curl 설치(슬림 이미지에는 기본 미포함)
# RUN apt-get update && apt-get install -y --no-install-recommends curl \
#  && rm -rf /var/lib/apt/lists/*

# HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
#   CMD curl -fsS http://127.0.0.1:${PORT}/health || exit 1

# USER appuser

# ARG APP_VERSION=v1.0
# ENV APP_VERSION=${APP_VERSION}
# EXPOSE 5000

# # 워커 2개로 gunicorn 실행 (app:app -> 파일명:변수명)
# CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "30", "app:app"]