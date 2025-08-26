#!/bin/bash
set -e
echo "Deploy web-test and run health check"

# 1. web-test 인스턴스 생성
instance_id=$(aws ec2 run-instances \
  --launch-template LaunchTemplateName="web-test-k" \
  --query 'Instances[0].InstanceId' \
  --output text)
echo "Web-test instance id: $instance_id"

# 2. 상태 ok 대기
aws ec2 wait instance-status-ok --instance-ids "$instance_id"
echo "Ec2 system status: ok"

# 3. web-test ip 조회
private_ip=$(aws ec2 describe-instances \
  --instance-ids "$instance_id" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)
echo "Web-test private ip: $private_ip"

# 4. 헬스 체크 루프
for i in $(seq 20); do
  echo "Health check attempt: $i/20"
  health_status=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/web-key.pem ubuntu@"$private_ip" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost/health" || echo "000")
  echo "App health status: $health_status"

  # 헬스 체크 통과
  if [ "$health_status" = "200" ]; then
    echo "Health check passed ✅"
    aws ec2 terminate-instances --instance-ids "$instance_id"
    rm -f ~/.ssh/web-key.pem
    echo "Instance terminated and key removed"
    break
  fi

  # 헬스 체크 실패
  if [ "$i" -eq 20 ]; then
    echo "Health check failed ❌"
    aws ec2 terminate-instances --instance-ids "$instance_id"
    rm -f ~/.ssh/web-key.pem
    echo "Instance terminated and key removed"
    exit 1
  fi
  sleep 10
done
