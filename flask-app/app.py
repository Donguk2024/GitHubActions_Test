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
        version="1.0.0",
        hostname=socket.gethostname(),
        time=datetime.datetime.utcnow().isoformat()
    ), 200


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
