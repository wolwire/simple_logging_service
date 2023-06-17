while true; do
  curl -X POST -H "Content-Type: application/json" -d '{
    "id": 1234,
    "unix_ts": 1684129671,
    "user_id": 123456,
    "event_name": "login"
  }' http://sinatra-app:4567/log
  
  sleep 0.001
done