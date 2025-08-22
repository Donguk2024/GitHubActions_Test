#!/bin/bash
set -e
echo "Rolling update ASG"
ASG_NAME="asg-webapp"
ORIGIN_MIN=0
ORIGIN_MAX=0
ORIGIN_DESIRED=0

# 인스턴스 상태 출력 함수
print_instance_states() {
  echo "현재 인스턴스 상태:"
  aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].Instances[*].[InstanceId, LifecycleState, HealthStatus]' \
    --output text
}
# 기존 용량 복구 함수
restore_capacity() {
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$ASG_NAME" \
    --min-size "$ORIGIN_MIN" \
    --max-size "$ORIGIN_MAX" \
    --desired-capacity "$ORIGIN_DESIRED"
  echo "용량 복원 완료: $ORIGIN_MIN(Min), $ORIGIN_MAX(Max), $ORIGIN_DESIRED(Desired)"
}

# 1. 기존 용량 설정 백업
ORIGIN_MIN=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].MinSize' --output text)
ORIGIN_MAX=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].MaxSize' --output text)
ORIGIN_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].DesiredCapacity' --output text)
echo "기존 용량: $ORIGIN_MIN(Min), $ORIGIN_MAX(Max), $ORIGIN_DESIRED(Desired)"

# 2. 교체 대상 인스턴스 파악
instances=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[?!starts_with(LifecycleState, `Terminating`)].InstanceId' \
  --output text)
read -ra instance_array <<< "$instances"
replace_count=${#instance_array[@]}
echo "교체 대상 인스턴스 ($replace_count개): ${instance_array[*]}"
print_instance_states

# 3. 용량 설정 변경 (교체할 인스턴스 수 + 1)
new_capacity=$((replace_count + 1))
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --min-size "$new_capacity" \
  --max-size "$new_capacity" \
  --desired-capacity "$new_capacity"
echo "용량 설정 변경: $replace_count → $new_capacity (Min=Max=Desired)"

# 4. 새 인스턴스가 Healthy 상태가 될 때까지 대기
for i in $(seq 20); do
  echo "새 인스턴스 Healthy 대기: $i/20"
  healthy_count=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService' && HealthStatus=='Healthy'])" \
    --output text)
  echo "총 Healthy 인스턴스 수: $healthy_count/$new_capacity"
  # 상태 확인 완료
  if [[ "$healthy_count" -ge "$new_capacity" ]]; then
    echo "✅ Healthy 확인 완료"
    print_instance_states
    break
  fi
  # 상태 확인 실패
  if [ "$i" -eq 20 ]; then
    echo "❌ Healthy 확인 실패"
    print_instance_states
    restore_capacity
    exit 1
  fi
  sleep 10
done

# 5. 대상 인스턴스들을 하나씩 교체
echo "인스턴스 롤링 교체 시작..."
for instance_id in "${instance_array[@]}"; do

  # 5.1 종료 요청
  echo "$instance_id 종료 요청"
  aws autoscaling terminate-instance-in-auto-scaling-group \
    --instance-id "$instance_id" \
    --no-should-decrement-desired-capacity

  # 5.2 terminating 상태가 될 때까지 대기
  for i in $(seq 20); do
    echo "$instance_id Terminating 대기: $i/20"
    lifecycle=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "$ASG_NAME" \
      --query "AutoScalingGroups[0].Instances[?InstanceId=='$instance_id'].LifecycleState" \
      --output text)
    echo "$instance_id 상태: $lifecycle"
    # 상태 확인 완료
    if [[ "$lifecycle" == Terminating* || -z "$lifecycle" ]]; then
      echo "✅ Terminating 확인 완료"
      print_instance_states
      break
    fi
    # 상태 확인 실패
    if [ "$i" -eq 20 ]; then
      echo "❌ Terminating 확인 실패"
      print_instance_states
      restore_capacity
      exit 1
    fi
    sleep 10
  done

  # 5.3 새 인스턴스가 Healthy 상태가 될 때까지 대기
  for i in $(seq 20); do
    echo "새 인스턴스 Healthy 대기: $i/20"
    healthy_count=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "$ASG_NAME" \
      --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService' && HealthStatus=='Healthy'])" \
      --output text)
    echo "총 Healthy 인스턴스 수: $healthy_count/$new_capacity"
    # 상태 확인 완료
    if [[ "$healthy_count" -ge "$new_capacity" ]]; then
      echo "✅ Healthy 확인 완료"
      print_instance_states
      break
    fi
    # 상태 확인 실패
    if [ "$i" -eq 20 ]; then
      echo "❌ Healthy 확인 실패"
      print_instance_states
      restore_capacity
      exit 1
    fi
    sleep 10
  done
done

# 6. 기존 용량 설정 복구
echo "롤링 업데이트 완료"
restore_capacity