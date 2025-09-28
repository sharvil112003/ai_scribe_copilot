# MediNote API + Flutter Integration

## Overview

This project provides a full-stack solution for managing medical records, patient interactions, and uploading audio sessions. It includes a mock backend API (Node.js + TypeScript) with endpoints for handling patient data, audio uploads, and session management. The Flutter frontend records audio sessions and uploads them in chunks to the backend.

### Key Features:

* **Backend (Node.js with TypeScript):**

  * REST API for managing patients, sessions, and templates.
  * Supports audio file uploads in chunks.
  * CORS-enabled to allow cross-origin requests from the frontend.
* **Frontend (Flutter):**

  * Records audio in AAC format.
  * Uploads audio in chunks to the backend.
  * Supports resuming uploads for long recordings.

---

## Loom ios Demo Video

For a demo of the MediNote app in action, check out this Loom video:

[Watch the MediNote Demo](https://drive.google.com/file/d/1yHoe57F5UXWMv6dd6hf8KSWcvJl8WeEF/view?usp=sharing)

## Prerequisites

Ensure you have the following installed:

* [Node.js](https://nodejs.org/) (v14.x or higher)
* [pnpm](https://pnpm.io/) (or npm/yarn as an alternative)
* [Flutter](https://flutter.dev/docs/get-started/install)
* [Docker](https://www.docker.com/get-started) (for containerized environment)
* [Android Studio](https://developer.android.com/studio) (for Flutter development)

---

## Project Structure

```
/project-root
├── backend
│   ├── Dockerfile            # Docker setup for backend API
│   ├── docker-compose.yml    # Docker Compose configuration for API and database
│   ├── src
│   │   ├── server.ts         # Express API server (Node.js + TypeScript)
│   │   ├── env.ts            # Environment variables
│   │   ├── api               # Routes for managing patients, sessions, templates
│   │   └── utils             # Helper functions for uploads, auth, etc.
│   ├── .env                  # Backend environment variables
│   └── package.json          # Backend dependencies and scripts
└── frontend
    ├── lib
    │   ├── rolling_recorder.dart  # Audio recording logic for Flutter
    │   ├── api_client.dart       # Client for interacting with the backend API
    │   └── upload_queue.dart     # Manages upload queue for audio chunks
    ├── android
    └── ios
    └── pubspec.yaml            # Flutter dependencies
    └── main.dart               # Flutter app entry point
```

---

## Backend Setup

### 1. Install Dependencies

Inside the `backend/` folder, install the required dependencies using `pnpm`:

```bash
cd backend
pnpm install
```

### 2. Environment Variables

Create a `.env` file in the `backend/` folder and configure the environment variables:

```env
PORT=3001
CORS_ORIGIN=*
NODE_ENV=development
```

You can change the values as needed. The `PORT` variable is the port the backend will run on, and `CORS_ORIGIN` specifies the allowed origins for CORS.

### 3. Docker Setup

To build and run the backend API in Docker, use the following command:

```bash
docker-compose up -d --build
```

This will:

* Build the backend Docker image
* Start the API service on port `3001` (or any custom port if specified in `.env`)

You can check if the server is running by accessing:

```
http://localhost:3001/health
```

The expected response is:

```json
{
  "status": "healthy",
  "timestamp": "2025-09-27T14:20:00Z",
  "version": "1.0.0"
}
```

### 4. Run Locally

If you want to run the backend server locally without Docker, run the following command:

```bash
pnpm run dev
```

This will start the backend server on `http://localhost:3001`.

---

## Frontend Setup (Flutter)

### 1. Install Dependencies

Inside the `frontend/` folder, run the following to install dependencies:

```bash
cd frontend
flutter pub get
```

### 2. Configure API Endpoint

In `lib/api_client.dart`, replace the `API_BASE_URL` with the actual IP address of your backend API. You can use `localhost` or the local IP address of your server 

```dart
class ApiClient {
  static const String baseUrl = 'http://x.x.x.X:3001';  // Replace with actual IP
  // Other API client logic
}
```

### 3. Run the Flutter App

Run the app on your Android/iOS device/emulator:

```bash
flutter run
```

### 4. Testing the Upload

You can now test audio recording and uploading in the Flutter app. The app will record audio and send it in chunks to the backend, which stores and processes the uploaded audio.

---

## Development Workflow

### 1. Start the Backend

Make sure your backend server is running in Docker or locally:

```bash
docker-compose up -d --build
# or
pnpm run dev
```

### 2. Start Flutter App

Open the Flutter app in your editor (VS Code, Android Studio, etc.), then run it:

```bash
flutter run
```

### 3. Test Features

* **Recording**: The Flutter app will record audio in chunks and send them to the backend.
* **Upload**: After each chunk is recorded, it will be uploaded to the backend via the `upload-chunk` endpoint.
* **Backend Logs**: You can check the server logs in the terminal to see the progress and uploads.

---

## Docker Commands

### Build and Start Containers

```bash
docker-compose up -d --build
```

### Stop Containers

```bash
docker-compose down
```

### View Logs

```bash
docker-compose logs -f
```

---

## API Documentation

For a list of all available API endpoints, visit:

```
http://localhost:3001/api/docs
```

The API includes endpoints for:

* Fetching patients
* Fetching session details
* Uploading audio chunks
* Managing templates

---

## Troubleshooting

* **Connection Refused Error**: Ensure that you are using the correct LAN IP address in the Flutter app. Use `http://<LAN-IP>:3001` for the backend URL.
* **CORS Issues**: If you run into CORS errors, ensure your backend is allowing requests from the correct frontend IP (configured in `.env`).

---

## Additional Notes

* The backend is built with **Node.js**, **Express**, and **TypeScript**.
* The frontend is built with **Flutter** and is set up to record and upload audio in **AAC** format.
* The backend uses **Docker** for containerized deployment, making it easy to deploy and scale.

---

This `README.md` should help guide you through the entire setup and workflow of your project. Let me know if you'd like any more details added!
