""" from flask import Flask
import os

app = Flask(__name__)

@app.route('/')
def hello():
    return f"Hello from Flask! Version: {os.getenv('APP_VERSION', 'v1.0')}"

@app.route('/health')
def health():
    return {"status": "healthy", "version": os.getenv('APP_VERSION', 'v1.0')}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000) """

from flask import Flask, jsonify
import socket
import datetime


app = Flask(__name__)

# 기본 페이지
@app.route('/')
def hello():
    return "Hello from Flask on EC2!", 200

# ALB 헬스체크용
@app.route('/health')
def health():
    return jsonify(status="healthy"), 200

# 상태 확인 (운영자용)
@app.route("/status")
def status():
    return jsonify(
        app="autoscaling-demo",
        version="1.1.3",
        hostname=socket.gethostname(),
        time=datetime.datetime.utcnow().isoformat()
    ), 200

# docker pull 확인
@app.route("/version")
def version():
    import os
    return {
        "app_version": os.getenv("APP_VERSION", "unknown"),
        "image_digest": os.getenv("IMAGE_DIGEST", "unknown")
    }, 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)