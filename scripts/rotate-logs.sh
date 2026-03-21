#!/bin/bash
# Скрипт для ротации логов Angie
# Запускать через cron: 0 2 * * * /path/to/project/scripts/rotate-logs.sh

set -e

# Настройте путь к вашему проекту
LOG_DIR="./logs"
KEEP_DAYS=30
# Название контейнера angie
ANGIE_CONT_NAME="angie"

cd "$LOG_DIR"

# Функция ротации лога
rotate_log() {
    local logfile="$1"
    local date_suffix=$(date +%Y%m%d-%H%M%S)
    
    if [ -f "$logfile" ] && [ -s "$logfile" ]; then
        # Копируем лог с датой
        cp "$logfile" "${logfile}.${date_suffix}"
        
        # Очищаем текущий лог
        truncate -s 0 "$logfile"
        
        # Сжимаем старый лог
        gzip "${logfile}.${date_suffix}"
        
        echo "Rotated: $logfile -> ${logfile}.${date_suffix}.gz"
    fi
}

# Ротация всех файлов, заканчивающихся на access.log
echo "=== Rotating access logs ==="
find "$LOG_DIR" -maxdepth 1 -type f -name "*access.log" | while read -r logfile; do
    rotate_log "$logfile"
done

# Ротация всех файлов, заканчивающихся на error.log
echo "=== Rotating error logs ==="
find "$LOG_DIR" -maxdepth 1 -type f -name "*error.log" | while read -r logfile; do
    rotate_log "$logfile"
done

# Ротация modsec_audit.log (если существует)
if [ -f "modsec_audit.log" ]; then
    echo "=== Rotating modsec_audit.log ==="
    rotate_log "modsec_audit.log"
fi

# Отправляем сигнал Angie для переоткрытия логов
docker exec $ANGIE_CONT_NAME angie -s reopen 2>/dev/null || echo "Warning: Could not reopen logs"

# Удаляем архивы логов старше KEEP_DAYS дней (ищет все сжатые логи, заканчивающиеся на .log.*.gz)
find "$LOG_DIR" -maxdepth 1 -type f \( -name "*access.log.*.gz" -o -name "*error.log.*.gz" -o -name "modsec_audit.log.*.gz" \) -mtime +"${KEEP_DAYS}" -delete
echo "Deleted logs older than ${KEEP_DAYS} days"

# Статистика
echo ""
echo "=== Current log sizes ==="
find "$LOG_DIR" -maxdepth 1 -type f \( -name "*access.log" -o -name "*error.log" -o -name "modsec_audit.log" \) -exec ls -lh {} \; 2>/dev/null || echo "No active logs"

echo ""
echo "=== Archived logs count ==="
echo "Access logs archives: $(find "$LOG_DIR" -maxdepth 1 -name "*access.log.*.gz" | wc -l)"
echo "Error logs archives: $(find "$LOG_DIR" -maxdepth 1 -name "*error.log.*.gz" | wc -l)"
echo "Modsec logs archives: $(find "$LOG_DIR" -maxdepth 1 -name "modsec_audit.log.*.gz" | wc -l)"
