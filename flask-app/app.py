
# from flask import Flask, jsonify
# import socket
# import datetime


# app = Flask(__name__)

# # 기본 페이지
# @app.route('/')
# def hello():
#     return "Hello from Flask on EC2!", 200

# # ALB 헬스체크용
# @app.route('/health')
# def health():
#     return jsonify(status="healthy"), 200

# # 상태 확인 (운영자용)
# @app.route("/status")
# def status():
#     return jsonify(
#         app="autoscaling-demo",
#         version="1.1.8",
#         hostname=socket.gethostname(),
#         time=datetime.datetime.utcnow().isoformat()
#     ), 200

# # docker pull 확인
# @app.route("/version")
# def version():
#     import os
#     return {
#         "app_version": os.getenv("APP_VERSION", "unknown"),
#         "image_digest": os.getenv("IMAGE_DIGEST", "unknown")
#     }, 200

# if __name__ == '__main__':
#     app.run(host='0.0.0.0', port=5000)

from flask import Flask, jsonify
import os
import socket
import datetime
import time
import threading
import mysql.connector

app = Flask(__name__)

@app.route('/')
def hello():
    return f"""
    <h1>Hello from Flask! Version: {os.getenv('APP_VERSION', 'v1.0')}</h1>
    <h2><a href="/event">Event</a></h2>
    <h2><a href="/db">DB</a></h2>
    """

@app.route('/health')
def health():
    return {"status": "healthy", "version": os.getenv('APP_VERSION', 'v1.0')}

@app.route('/event')
def event():
    return '<html><body><img src="/static/event.png"></body></html>'

# 상태 확인 (운영자용)
@app.route("/status")
def status():
    return jsonify(
        app="autoscaling-demo",
        version="1.1.9",
        hostname=socket.gethostname(),
        time=datetime.datetime.utcnow().isoformat()
    ), 200

# @app.route('/db')
# def db():
#     def hold_connection():
#         try:
#             conn = mysql.connector.connect(
#                 host=os.getenv('DB_HOST'),
#                 port=int(os.getenv('DB_PORT', 3306)),
#                 user=os.getenv('DB_USERNAME'),
#                 password=os.getenv('DB_PASSWORD')
#             )
#             time.sleep(60)
#             conn.close()
#             print("DB connection completed")
#         except Exception as e:
#             print(f"DB connection failed: {e}")
#     threading.Thread(target=hold_connection).start()
#     return "<h1>DB connection started</h1>"

