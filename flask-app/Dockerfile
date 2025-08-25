FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN ls -l /app && test -f /app/app.py  # 없으면 빌드 실패
RUN pip install -r requirements.txt
COPY . .
ARG APP_VERSION=v1.0
ENV APP_VERSION=${APP_VERSION}
EXPOSE 5000
CMD ["python", "app.py"]
