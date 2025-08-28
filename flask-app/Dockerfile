# FROM python:3.9-slim

# # 기본 환경
# ENV PYTHONUNBUFFERED=1 \
#     PIP_NO_CACHE_DIR=1 \
#     PORT=5000 \
#     GUNICORN_WORKERS=2 \
#     GUNICORN_TIMEOUT=30

# WORKDIR /app

# # 의존성 먼저(캐시 최적화)
# COPY requirements.txt .
# RUN pip install --upgrade pip && \
#     pip install --no-cache-dir -r requirements.txt

# # 앱 복사 + 권한
# COPY --chown=appuser:appuser . .
# RUN useradd -m appuser
# USER appuser

# HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
#   CMD ["python","-c","import os,urllib.request,sys;port=os.getenv('PORT','5000');url='http://127.0.0.1:'+port+'/health';\
# import urllib.error; \
# try: \
#     r=urllib.request.urlopen(url,timeout=2); sys.exit(0 if r.status==200 else 1) \
# except Exception: \
#     sys.exit(1)"]

# ARG APP_VERSION=v1.0
# ENV APP_VERSION=${APP_VERSION}

# EXPOSE 5000

# # 운영 권장: gunicorn
# # (requirements.txt에 gunicorn 포함 필요)
# CMD ["sh","-c","exec gunicorn -w ${GUNICORN_WORKERS} -t ${GUNICORN_TIMEOUT} -b 0.0.0.0:${PORT} app:app"]

FROM python:3.12-slim

# 보안/재현성에 유리한 기본 설정
ENV PYTHONUNBUFFERED=1 \
    PORT=5000 \
    GUNICORN_WORKERS=2 \
    GUNICORN_TIMEOUT=30

WORKDIR /app

# 의존성 먼저 설치 (빌드 캐시 최적화)
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && useradd -m appuser

# 소스 복사
COPY . .

# 컨테이너 내부 헬스체크(옵션)
# curl 설치(슬림 이미지에는 기본 미포함)
RUN apt-get update && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -fsS http://127.0.0.1:${PORT}/health || exit 1

USER appuser

ARG APP_VERSION=v1.0
ENV APP_VERSION=${APP_VERSION}
EXPOSE 5000

# 워커 2개로 gunicorn 실행 (app:app -> 파일명:변수명)
CMD ["python", "app.py"]

# FROM python:3.9-slim

# # 기본 환경
# ENV PYTHONUNBUFFERED=1 \
#     PIP_NO_CACHE_DIR=1 \
#     PORT=5000 \
#     GUNICORN_WORKERS=2 \
#     GUNICORN_TIMEOUT=30
    
# WORKDIR /app

# COPY requirements.txt .
# RUN pip install -r requirements.txt

# COPY . .
# ARG APP_VERSION=v1.0
# ENV APP_VERSION=${APP_VERSION}
# EXPOSE 5000

# RUN ls -l /app && test -f /app/app.py  # 없으면 빌드 실패
# CMD ["python", "app.py"]FROM python:3.9-slim