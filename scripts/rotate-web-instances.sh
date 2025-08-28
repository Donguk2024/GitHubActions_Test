#!/bin/bash
set -euo pipefail

echo "Rolling update ASG (batch/parallel)"

# === 파라미터 (요청: 이 두 줄은 변경하지 않음) ============================
BATCH_SIZE=${BATCH_SIZE:-2}   # 한 번에 몇 대를 교체할지
BUFFER=${BUFFER:-$BATCH_SIZE} # 여유 용량 (new_capacity = 기존 + BUFFER)
# ======================================================================

# 추가 파라미터 (필요 시 환경변수로 덮어쓰기)
ASG_NAME=${ASG_NAME:-"asg-k"}
HEALTH_TIMEOUT_SEC=${HEALTH_TIMEOUT_SEC:-900}  # 한 배치에서 Healthy 대기 최대 15분
POLL_INTERVAL_SEC=${POLL_INTERVAL_SEC:-10}     # 폴링 주기
DRY_RUN=${DRY_RUN:-0}                          # 1이면 변경 없이 동작 검증

# 상태 출력 함수
print_instance_states() {
  echo "현재 인스턴스 상태:"
  aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].Instances[*].[InstanceId, LifecycleState, HealthStatus]' \
    --output text
}

# 기존 용량 복구 함수
restore_capacity() {
  echo "용량 복구: Min=$ORIGIN_MIN, Max=$ORIGIN_MAX, Desired=$ORIGIN_DESIRED"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    aws autoscaling update-auto-scaling-group \
      --auto-scaling-group-name "$ASG_NAME" \
      --min-size "$ORIGIN_MIN" \
      --max-size "$ORIGIN_MAX" \
      --desired-capacity "$ORIGIN_DESIRED"
  else
    echo "[DRY RUN] ASG 용량 복구 생략"
  fi
  echo "용량 복구 완료"
}

# 안전 종료 트랩
trap 'echo "오류/중단 감지 → 용량 복구 시도"; restore_capacity' INT TERM ERR

# 1) 기존 용량 백업
ORIGIN_MIN=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].MinSize' --output text)
ORIGIN_MAX=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].MaxSize' --output text)
ORIGIN_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].DesiredCapacity' --output text)
echo "기존 용량: Min=$ORIGIN_MIN, Max=$ORIGIN_MAX, Desired=$ORIGIN_DESIRED"

# 2) 교체 대상 인스턴스 파악 (Terminating* 제외)
instances=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[?!starts_with(LifecycleState, `Terminating`)].InstanceId' \
  --output text)
read -ra instance_array <<< "$instances"
replace_count=${#instance_array[@]}
if (( replace_count == 0 )); then
  echo "교체할 인스턴스가 없습니다. 종료합니다."
  exit 0
fi
echo "교체 대상 인스턴스 ($replace_count개): ${instance_array[*]}"
print_instance_states

# 배치 사이즈/버퍼 검증
if (( BATCH_SIZE <= 0 )); then
  echo "BATCH_SIZE는 1 이상이어야 합니다." >&2
  exit 1
fi
if (( BUFFER <= 0 )); then
  echo "BUFFER는 1 이상이어야 합니다." >&2
  exit 1
fi
if (( BATCH_SIZE > BUFFER )); then
  echo "경고: BATCH_SIZE($BATCH_SIZE) > BUFFER($BUFFER). 서비스 안정성을 위해 BUFFER ≥ BATCH_SIZE 권장."
fi

# 3) 버퍼 확보를 위해 용량 확장
new_capacity=$((replace_count + BUFFER))
echo "용량 확장: NewCapacity=$new_capacity (BUFFER=$BUFFER)"
if [[ "$DRY_RUN" -eq 0 ]]; then
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$ASG_NAME" \
    --min-size "$new_capacity" \
    --max-size "$new_capacity" \
    --desired-capacity "$new_capacity"
else
  echo "[DRY RUN] ASG 용량 확장 생략"
fi

# Healthy 카운팅 함수
get_healthy_count() {
  aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService' && HealthStatus=='Healthy'])" \
    --output text
}

# Healthy 대기 공통 함수 (전체 healthy가 new_capacity 이상)
wait_for_healthy_all() {
  local deadline=$((SECONDS + HEALTH_TIMEOUT_SEC))
  while (( SECONDS < deadline )); do
    local healthy_count
    healthy_count=$(get_healthy_count)
    echo "총 Healthy 인스턴스 수: $healthy_count/$new_capacity (대상=$new_capacity)"
    if (( healthy_count >= new_capacity )); then
      echo "✅ Healthy 충족"
      print_instance_states
      return 0
    fi
    sleep "$POLL_INTERVAL_SEC"
  done
  echo "❌ Healthy 확인 실패 (타임아웃 ${HEALTH_TIMEOUT_SEC}s)"
  return 1
}

# 4) 초기 버퍼까지 Healthy 대기
echo "초기 Healthy 대기 중..."
wait_for_healthy_all

# 5) 배치/병렬 교체
echo "배치 병렬 교체 시작... (BATCH_SIZE=$BATCH_SIZE, BUFFER=$BUFFER)"
for ((idx=0; idx<replace_count; idx+=BATCH_SIZE)); do
  # 이번 배치 추출
  batch=( "${instance_array[@]:idx:BATCH_SIZE}" )
  echo "배치 종료 요청: ${batch[*]}"

  # 5.1 병렬 종료 요청
  if [[ "$DRY_RUN" -eq 0 ]]; then
    for instance_id in "${batch[@]}"; do
      aws autoscaling terminate-instance-in-auto-scaling-group \
        --instance-id "$instance_id" \
        --no-should-decrement-desired-capacity &
    done
    wait  # 종료 요청 전송 완료 대기
  else
    echo "[DRY RUN] terminate-instance-in-auto-scaling-group 생략: ${batch[*]}"
  fi

  # 5.2 배치 후 전체 Healthy가 new_capacity 도달할 때까지 대기
  echo "배치 Healthy 대기..."
  wait_for_healthy_all
done

# 6) 기존 용량 복구
echo "롤링 업데이트 완료. 기존 용량으로 복구합니다."
restore_capacity

# 트랩 해제 (정상 종료)
trap - INT TERM ERR
echo "✅ 완료"


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

# # 3. 용량 설정 변경 (교체할 인스턴스 수 + 2)
# new_capacity=$((replace_count + 2))
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

