# Study With Me

## 실행 방법
python3 -m pip install -r requirements.txt

### 1. 백엔드

```powershell
cd backend
python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### 2. 프론트엔드

새 터미널에서 실행:

```powershell
cd frontend
flutter pub get
flutter run -d chrome --web-port 8082 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

접속 주소:

```text
http://127.0.0.1:8082
```

코드를 수정한 뒤 터미널에서:

```text
r  Hot reload
R  Hot restart
q  종료
```
