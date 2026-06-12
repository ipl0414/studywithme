# Study With Me

FastAPI 백엔드와 Flutter 프론트엔드로 구성된 AI tutor 학습 앱 프로토타입입니다.

## Repository

```text
backend/
  app/               FastAPI 소스
  .env.example       환경변수 예시
  requirements.txt   Python 패키지

frontend/
  lib/               Flutter 소스
  assets/            앱 정적 파일
  web/               Flutter Web 설정
  android/           Android 빌드 설정
  pubspec.yaml       Flutter 패키지
```

로컬 `.env`, 생성 이미지, 로그, 빌드 결과, 테스트, 데모 및 발표 자료는 Git에 포함하지 않습니다.

## Backend

Python 3.11 이상을 권장합니다.

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
```

`backend/.env`에 사용할 API 키와 모델을 설정합니다. 이미지 생성을 생략하려면 다음 값을 사용합니다.

```env
TEST_NO_IMAGE=yes
```

실제 캐릭터 이미지를 생성하려면 `GEMINI_API_KEY`를 입력하고 다음 값을 변경합니다.

```env
TEST_NO_IMAGE=no
```

서버 실행:

```powershell
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

확인 주소:

```text
http://127.0.0.1:8000/health
http://127.0.0.1:8000/docs
```

## Flutter Web

Flutter 3.41 이상을 권장합니다.

```powershell
cd frontend
flutter pub get
flutter run -d chrome --web-port 8082 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

브라우저 주소:

```text
http://127.0.0.1:8082
```

## Android Emulator

백엔드를 `--host 0.0.0.0`으로 실행한 상태에서:

```powershell
cd frontend
flutter pub get
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`emulator-5554`가 다르면 `flutter devices`에 표시되는 device ID를 사용합니다.

## GitHub Upload

```powershell
git init
git add .
git status
git commit -m "Initial Study With Me prototype"
git branch -M main
git remote add origin https://github.com/OWNER/REPOSITORY.git
git push -u origin main
```

`git status`에서 `backend/.env`, `backend/generated`, `frontend/build` 파일이 보이면 커밋하지 마세요.
