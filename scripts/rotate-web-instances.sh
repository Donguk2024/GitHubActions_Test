# #!/bin/bash
# set -e
# echo "Rolling update ASG"
# ASG_NAME="asg-k"
# ORIGIN_MIN=0
# ORIGIN_MAX=0
# ORIGIN_DESIRED=0

# # 인스턴스 상태 출력 함수
# print_instance_states() {
#   echo "현재 인스턴스 상태:"
#   aws autoscaling describe-auto-scaling-groups \
#     --auto-scaling-group-names "$ASG_NAME" \
#     --query 'AutoScalingGroups[0].Instances[*].[InstanceId, LifecycleState, HealthStatus]' \
#     --output text
# }
# # 기존 용량 복구 함수
# restore_capacity() {
#   aws autoscaling update-auto-scaling-group \
#     --auto-scaling-group-name "$ASG_NAME" \
#     --min-size "$ORIGIN_MIN" \
#     --max-size "$ORIGIN_MAX" \
#     --desired-capacity "$ORIGIN_DESIRED"
#   echo "용량 복원 완료: $ORIGIN_MIN(Min), $ORIGIN_MAX(Max), $ORIGIN_DESIRED(Desired)"
# }

# # 1. 기존 용량 설정 백업
# ORIGIN_MIN=$(aws autoscaling describe-auto-scaling-groups \
#   --auto-scaling-group-names "$ASG_NAME" \
#   --query 'AutoScalingGroups[0].MinSize' --output text)
# ORIGIN_MAX=$(aws autoscaling describe-auto-scaling-groups \
#   --auto-scaling-group-names "$ASG_NAME" \
#   --query 'AutoScalingGroups[0].MaxSize' --output text)
# ORIGIN_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
#   --auto-scaling-group-names "$ASG_NAME" \
#   --query 'AutoScalingGroups[0].DesiredCapacity' --output text)
# echo "기존 용량: $ORIGIN_MIN(Min), $ORIGIN_MAX(Max), $ORIGIN_DESIRED(Desired)"

# # 2. 교체 대상 인스턴스 파악
# instances=$(aws autoscaling describe-auto-scaling-groups \
#   --auto-scaling-group-names "$ASG_NAME" \
#   --query 'AutoScalingGroups[0].Instances[?!starts_with(LifecycleState, `Terminating`)].InstanceId' \
#   --output text)
# read -ra instance_array <<< "$instances"
# replace_count=${#instance_array[@]}
# echo "교체 대상 인스턴스 ($replace_count개): ${instance_array[*]}"
# print_instance_states

# # 3. 용량 설정 변경 (교체할 인스턴스 수 + 1)
# new_capacity=$((replace_count + 1))
# aws autoscaling update-auto-scaling-group \
#   --auto-scaling-group-name "$ASG_NAME" \
#   --min-size "$new_capacity" \
#   --max-size "$new_capacity" \
#   --desired-capacity "$new_capacity"
# echo "용량 설정 변경: $replace_count → $new_capacity (Min=Max=Desired)"

# # 4. 새 인스턴스가 Healthy 상태가 될 때까지 대기
# for i in $(seq 20); do
#   echo "새 인스턴스 Healthy 대기: $i/20"
#   healthy_count=$(aws autoscaling describe-auto-scaling-groups \
#     --auto-scaling-group-names "$ASG_NAME" \
#     --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService' && HealthStatus=='Healthy'])" \
#     --output text)
#   echo "총 Healthy 인스턴스 수: $healthy_count/$new_capacity"
#   # 상태 확인 완료
#   if [[ "$healthy_count" -ge "$new_capacity" ]]; then
#     echo "✅ Healthy 확인 완료"
#     print_instance_states
#     break
#   fi
#   # 상태 확인 실패
#   if [ "$i" -eq 20 ]; then
#     echo "❌ Healthy 확인 실패"
#     print_instance_states
#     restore_capacity
#     exit 1
#   fi
#   sleep 10
# done

# # 5. 대상 인스턴스들을 하나씩 교체
# echo "인스턴스 롤링 교체 시작..."
# for instance_id in "${instance_array[@]}"; do

#   # 5.1 종료 요청
#   echo "$instance_id 종료 요청"
#   aws autoscaling terminate-instance-in-auto-scaling-group \
#     --instance-id "$instance_id" \
#     --no-should-decrement-desired-capacity

#   # 5.2 terminating 상태가 될 때까지 대기
#   for i in $(seq 20); do
#     echo "$instance_id Terminating 대기: $i/20"
#     lifecycle=$(aws autoscaling describe-auto-scaling-groups \
#       --auto-scaling-group-names "$ASG_NAME" \
#       --query "AutoScalingGroups[0].Instances[?InstanceId=='$instance_id'].LifecycleState" \
#       --output text)
#     echo "$instance_id 상태: $lifecycle"
#     # 상태 확인 완료
#     if [[ "$lifecycle" == Terminating* || -z "$lifecycle" ]]; then
#       echo "✅ Terminating 확인 완료"
#       print_instance_states
#       break
#     fi
#     # 상태 확인 실패
#     if [ "$i" -eq 20 ]; then
#       echo "❌ Terminating 확인 실패"
#       print_instance_states
#       restore_capacity
#       exit 1
#     fi
#     sleep 10
#   done

#   # 5.3 새 인스턴스가 Healthy 상태가 될 때까지 대기
#   for i in $(seq 20); do
#     echo "새 인스턴스 Healthy 대기: $i/20"
#     healthy_count=$(aws autoscaling describe-auto-scaling-groups \
#       --auto-scaling-group-names "$ASG_NAME" \
#       --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService' && HealthStatus=='Healthy'])" \
#       --output text)
#     echo "총 Healthy 인스턴스 수: $healthy_count/$new_capacity"
#     # 상태 확인 완료
#     if [[ "$healthy_count" -ge "$new_capacity" ]]; then
#       echo "✅ Healthy 확인 완료"
#       print_instance_states
#       break
#     fi
#     # 상태 확인 실패
#     if [ "$i" -eq 20 ]; then
#       echo "❌ Healthy 확인 실패"
#       print_instance_states
#       restore_capacity
#       exit 1
#     fi
#     sleep 10
#   done
# done

# # 6. 기존 용량 설정 복구
# echo "롤링 업데이트 완료"
# restore_capacity

#!/bin/bash
set -Eeuo pipefail

ASG_NAME="asg-k"
SURGE=$(
  # 교체 대상 수가 2대 이상이면 +2, 아니면 +1
  replace_count=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'length(AutoScalingGroups[0].Instances[?!starts_with(LifecycleState, `Terminating`)])' \
    --output text)
  if (( replace_count >= 2 )); then echo 2; else echo 1; fi
)

# 현재 용량 백업
read ORIGIN_MIN ORIGIN_MAX ORIGIN_DESIRED < <(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query '[AutoScalingGroups[0].MinSize, AutoScalingGroups[0].MaxSize, AutoScalingGroups[0].DesiredCapacity]' \
  --output text)

restore_capacity() {
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$ASG_NAME" \
    --min-size "$ORIGIN_MIN" --max-size "$ORIGIN_MAX" --desired-capacity "$ORIGIN_DESIRED" >/dev/null
  echo "용량 복구: Min=${ORIGIN_MIN}, Max=${ORIGIN_MAX}, Desired=${ORIGIN_DESIRED}"
}
trap 'restore_capacity' EXIT

# ASG 상세
ASG_JSON=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME")
TARGET_GROUP_ARN=$(echo "$ASG_JSON" | jq -r '.AutoScalingGroups[0].TargetGroupARNs[0]')
mapfile -t INSTANCE_IDS < <(echo "$ASG_JSON" | jq -r '.AutoScalingGroups[0].Instances[] | select(.LifecycleState|startswith("Terminating")|not) | .InstanceId')
replace_count=${#INSTANCE_IDS[@]}
echo "교체 대상: ${replace_count}개 => ${INSTANCE_IDS[*]}"

# 서지 반영
new_capacity=$((replace_count + SURGE))
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --min-size "$new_capacity" --max-size "$new_capacity" --desired-capacity "$new_capacity" >/dev/null
echo "용량 설정: Min=Max=Desired=${new_capacity} (서지 +${SURGE})"

# 함수: 대상 그룹 Healthy 수 계산
healthy_targets() {
  aws elbv2 describe-target-health --target-group-arn "$TARGET_GROUP_ARN" \
    --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text 2>/dev/null || echo 0
}

# 새 인스턴스 올라올 때까지 빠른 폴링(최대 90초)
deadline=$((SECONDS + 90))
while (( SECONDS < deadline )); do
  h=$(healthy_targets)
  echo "TargetGroup Healthy: ${h}/${new_capacity}"
  if (( h >= new_capacity )); then
    echo "✅ 새 인스턴스 Healthy 확인"
    break
  fi
  sleep 3
done
if (( SECONDS >= deadline )); then
  echo "❌ 새 인스턴스 Healthy 타임아웃"
  exit 1
fi

# 롤링: 하나씩 Standby → 디등록 → 확인 → terminate
for id in "${INSTANCE_IDS[@]}"; do
  echo "인스턴스 교체: $id → Standby"
  aws autoscaling enter-standby --auto-scaling-group-name "$ASG_NAME" --instance-ids "$id" \
    --should-decrement-desired-capacity >/dev/null

  # 디등록(타겟에서 제거)
  aws elbv2 deregister-targets --target-group-arn "$TARGET_GROUP_ARN" --targets Id="$id" >/dev/null

  # 타겟에서 사라질 때까지 기다림(짧게)
  deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    count=$(aws elbv2 describe-target-health --target-group-arn "$TARGET_GROUP_ARN" \
      --query "length(TargetHealthDescriptions[?Target.Id=='$id'])" --output text 2>/dev/null || echo 0)
    echo "디등록 대기: 남은 타겟 레코드 $count"
    (( count == 0 )) && break
    sleep 3
  done

  # 동일 Healthy 수 유지 확인 (원상복귀)
  deadline=$((SECONDS + 90))
  while (( SECONDS < deadline )); do
    h=$(healthy_targets)
    echo "Healthy 유지 확인: ${h}/${new_capacity}"
    if (( h >= new_capacity )); then break; fi
    sleep 3
  done

  # Standby 인스턴스 종료(용량은 유지 → 대체 인스턴스 자동 생성)
  echo "종료: $id"
  aws ec2 terminate-instances --instance-ids "$id" >/dev/null

  # 새로 추가된 인스턴스가 Healthy 될 때까지 대기
  deadline=$((SECONDS + 120))
  while (( SECONDS < deadline )); do
    h=$(healthy_targets)
    echo "새 Healthy 대기: ${h}/${new_capacity}"
    if (( h >= new_capacity )); then
      echo "✅ 배치 완료"
      break
    fi
    sleep 3
  done
  if (( SECONDS >= deadline )); then
    echo "❌ 새 Healthy 타임아웃"
    exit 1
  fi
done

echo "롤링 완료. 원 용량 복구."
restore_capacity
trap - EXIT
