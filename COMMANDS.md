# Project Commands Reference

---

## BACKEND (Laravel — PHP)

### PHP & Composer Location
```
PHP:      C:\Users\Dell\php82\php.exe
Composer: C:\Users\Dell\php82\composer.phar
Project:  E:\A project\ADRS all\loagma_crm_new\server
```

---

### Start Server

**For local browser / emulator:**
```
C:\Users\Dell\php82\php.exe "E:\A project\ADRS all\loagma_crm_new\server\artisan" serve
```

**For physical phone over LAN (recommended):**
```
C:\Users\Dell\php82\php.exe "E:\A project\ADRS all\loagma_crm_new\server\artisan" serve --host=0.0.0.0 --port=8000
```

---

### First-Time Setup (run once)

**1. Install dependencies:**
```
C:\Users\Dell\php82\php.exe "C:\Users\Dell\php82\composer.phar" install --working-dir="E:\A project\ADRS all\loagma_crm_new\server"
```

**2. Generate app key (if APP_KEY is empty):**
```
C:\Users\Dell\php82\php.exe "E:\A project\ADRS all\loagma_crm_new\server\artisan" key:generate
```

**3. Generate JWT secret (if JWT_SECRET is empty):**
```
C:\Users\Dell\php82\php.exe "E:\A project\ADRS all\loagma_crm_new\server\artisan" jwt:secret
```

**4. Run database migrations:**
```
C:\Users\Dell\php82\php.exe "E:\A project\ADRS all\loagma_crm_new\server\artisan" migrate
```

---

### Common Artisan Commands

**Check migration status:**
```
C:\Users\Dell\php82\php.exe "E:\A project\ADRS all\loagma_crm_new\server\artisan" migrate:status
```

**List all routes:**
```
C:\Users\Dell\php82\php.exe "E:\A project\ADRS all\loagma_crm_new\server\artisan" route:list
```

**Clear all caches:**
```
C:\Users\Dell\php82\php.exe "E:\A project\ADRS all\loagma_crm_new\server\artisan" optimize:clear
```

**Check DB connection:**
```
C:\Users\Dell\php82\php.exe "E:\A project\ADRS all\loagma_crm_new\server\artisan" db:show
```

---

### Backend URLs
| Target        | URL                            |
|---------------|--------------------------------|
| Local browser | http://localhost:8000          |
| LAN / phone   | http://10.29.126.87:8000       |
| Android emulator | http://10.0.2.2:8000        |

---
---

## FRONTEND (Flutter)

### Project Location
```
E:\A project\ADRS all\loagma_crm_new\client
```

---

### Run App

**On connected Android phone (over LAN):**
```
flutter run --device-id=002987649002082 --dart-define=API_BASE_URL=http://10.29.126.87:8000
```

**On Android emulator:**
```
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

**On Windows desktop:**
```
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:8000
```

**On Chrome (web):**
```
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

---

### Build Commands

**Build for Android APK (release):**
```
flutter build apk --release --dart-define=API_BASE_URL=http://10.29.126.87:8000
```

**Build for Windows EXE (release):**
```
flutter build windows --release
```

**Build for Web (release):**
```
flutter build web --release
```

---

### First-Time Setup (run once)

**Install Flutter dependencies:**
```
flutter pub get
```

**Check Flutter environment:**
```
flutter doctor
```

**List connected devices:**
```
flutter devices
```

---

### Installer Build Steps (Windows)
```
1. flutter build windows --release
2. Copy build\windows\x64\runner\Release\*  →  installer_output\Release\
3. Update MyAppVersion in installer.iss
4. Open installer.iss in Inno Setup
5. Press Ctrl + F9
6. Get setup.exe from installer_output\
```

---

## CURRENT DEVICE INFO

| Item            | Value                        |
|-----------------|------------------------------|
| Machine LAN IP  | 10.29.126.87                 |
| Android device  | A069 (ID: 002987649002082)   |
| Android version | Android 16 (API 36)          |
| Flutter version | 3.41.0                       |
| PHP version     | 8.2.31                       |
| Database        | TiDB Cloud MySQL (loagma_new) |
