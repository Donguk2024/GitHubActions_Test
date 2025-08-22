FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
ARG APP_VERSION=v1.0
ENV APP_VERSION=${APP_VERSION}
EXPOSE 5000
CMD ["python", "app.py"]
