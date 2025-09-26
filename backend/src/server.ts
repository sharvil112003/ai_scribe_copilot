import express, { Request, Response, NextFunction } from "express";
import cors from "cors";
import { randomUUID } from "node:crypto";
import path from "node:path";
import fs from "node:fs/promises";
import dotenv from "dotenv";

dotenv.config();

const app = express();
const PORT = Number(process.env.PORT || 3001);

// Middleware
app.use(cors({ origin: process.env.CORS_ORIGIN || "*", credentials: true }));
app.use(express.json({ limit: "50mb" }));
app.use(express.raw({ type: ["audio/*", "application/octet-stream"], limit: "50mb" }));

const uploadsDir = path.join(process.cwd(), "uploads");
fs.mkdir(uploadsDir, { recursive: true }).catch(() => {});

// --- In-memory data ---
type User = { id: string; email: string; name: string };
type Patient = {
  id: string; name: string; user_id: string; pronouns: string | null;
  email: string | null; background: string | null; medical_history: string | null;
  family_history: string | null; social_history: string | null; previous_treatment: string | null;
};
type Template = { id: string; title: string; type: string; userId: string };
type Session = {
  id: string; user_id: string; patient_id: string; patient_name?: string | null;
  session_title: string | null; session_summary: string | null;
  transcript_status: string | null; transcript: string | null; status: string;
  date: string; start_time: string; end_time: string | null; duration: string | null;
  template_id?: string | null; clinical_notes: any[];
};

const users: User[] = [
  { id: "user_123", email: "john.doe@example.com", name: "John Doe" },
  { id: "user_456", email: "jane.smith@example.com", name: "Jane Smith" },
];

const patients: Patient[] = [
  {
    id: "patient_123", name: "Alice Johnson", user_id: "user_123", pronouns: "she/her",
    email: "alice.johnson@example.com", background: "Regular patient", medical_history: "Type 2 diabetes",
    family_history: "Diabetes", social_history: "Active", previous_treatment: "Metformin"
  },
  {
    id: "patient_456", name: "Bob Wilson", user_id: "user_123", pronouns: "he/him",
    email: "bob.wilson@example.com", background: "New patient", medical_history: "Allergies",
    family_history: "None", social_history: "Active", previous_treatment: "Antihistamines"
  },
];

const templates: Template[] = [
  { id: "template_123", title: "New Patient Visit", type: "default", userId: "user_123" },
  { id: "template_456", title: "Follow-up Visit", type: "predefined", userId: "user_123" },
];

const sessions: Session[] = [
  {
    id: "session_123",
    user_id: "user_123",
    patient_id: "patient_123",
    patient_name: "Alice Johnson",
    session_title: "Diabetes Follow-up",
    session_summary: "Discussed medication adjustments",
    transcript_status: "completed",
    transcript: "Doctor: ... Patient: ...",
    status: "completed",
    date: "2024-01-15",
    start_time: "2024-01-15T10:00:00Z",
    end_time: "2024-01-15T10:30:00Z",
    duration: "30 minutes",
    template_id: "template_456",
    clinical_notes: []
  }
];

const audioChunks: Record<string, Record<string, any>> = {};

// --- Helpers ---
function presigned(sessionId: string, chunkNumber: number) {
  const baseUrl = `http://localhost:${PORT}`;
  return {
    url: `${baseUrl}/api/upload-chunk/${sessionId}/${chunkNumber}`,
    gcsPath: `sessions/${sessionId}/chunk_${chunkNumber}.wav`,
    publicUrl: `${baseUrl}/api/audio/${sessionId}/chunk_${chunkNumber}.wav`,
  };
}

function auth(req: Request, res: Response, next: NextFunction) {
  const header = req.header("Authorization");
  const token = header?.split(" ")[1];
  if (!token) return res.status(401).json({ error: "Access token required" });
  if (!token.startsWith("demo_") && !token.startsWith("eyJ")) {
    return res.status(401).json({ error: "Invalid token format" });
  }
  (req as any).user = { id: "user_123" };
  next();
}

// --- System ---
app.get("/health", (_req, res) => {
  res.json({ status: "healthy", timestamp: new Date().toISOString(), version: "1.0.0" });
});

app.get("/api/docs", (_req, res) => {
  res.json({
    title: "MediNote Mock API (TS)",
    version: "1.0.0",
    endpoints: [
      "GET /health",
      "GET /api/v1/patients",
      "POST /api/v1/add-patient-ext",
      "GET /api/v1/patient-details/:patientId",
      "GET /api/v1/fetch-session-by-patient/:patientId",
      "GET /api/v1/all-session",
      "GET /api/v1/fetch-default-template-ext",
      "POST /api/v1/upload-session",
      "POST /api/v1/get-presigned-url",
      "PUT /api/upload-chunk/:sessionId/:chunkNumber",
      "POST /api/v1/notify-chunk-uploaded",
      "GET /api/debug/all-data",
      "GET /api/debug/chunks/:sessionId"
    ]
  });
});

// --- Patient Management ---
app.get("/api/v1/patients", auth, (req, res) => {
  const userId = String(req.query.userId || "");
  if (!userId) return res.status(400).json({ error: "userId parameter required" });
  const list = patients.filter(p => p.user_id === userId).map(p => ({ id: p.id, name: p.name }));
  res.json({ patients: list });
});

app.get("/api/users/asd3fd2faec", auth, (req, res) => {
  const email = String(req.query.email || "");
  if (!email) return res.status(400).json({ error: "email parameter required" });
  const user = users.find(u => u.email === email);
  if (!user) return res.status(404).json({ error: "User not found" });
  res.json({ id: user.id });
});

app.post("/api/v1/add-patient-ext", auth, (req, res) => {
  const { name, userId } = req.body ?? {};
  if (!name || !userId) return res.status(400).json({ error: "name and userId are required" });
  const id = `patient_${randomUUID()}`;
  const patient: Patient = {
    id, name, user_id: userId, pronouns: null, email: null,
    background: null, medical_history: null, family_history: null,
    social_history: null, previous_treatment: null
  };
  patients.push(patient);
  res.status(201).json({ patient });
});

app.get("/api/v1/patient-details/:patientId", auth, (req, res) => {
  const p = patients.find(x => x.id === req.params.patientId);
  if (!p) return res.status(404).json({ error: "Patient not found" });
  res.json(p);
});

app.get("/api/v1/fetch-session-by-patient/:patientId", auth, (req, res) => {
  const list = sessions.filter(s => s.patient_id === req.params.patientId).map(s => ({
    id: s.id, date: s.date, session_title: s.session_title, session_summary: s.session_summary, start_time: s.start_time
  }));
  res.json({ sessions: list });
});

app.get("/api/v1/all-session", auth, (req, res) => {
  const userId = String(req.query.userId || "");
  if (!userId) return res.status(400).json({ error: "userId parameter required" });
  const userSessions = sessions.filter(s => s.user_id === userId);
  const patientMap: Record<string, any> = {};
  for (const p of patients) patientMap[p.id] = { name: p.name, pronouns: p.pronouns };
  const enriched = userSessions.map(s => {
    const p = patients.find(pp => pp.id === s.patient_id);
    return {
      ...s,
      patient_name: p?.name ?? "Unknown Patient",
      pronouns: p?.pronouns ?? null,
      email: p?.email ?? null,
      background: p?.background ?? null,
      medical_history: p?.medical_history ?? null,
      family_history: p?.family_history ?? null,
      social_history: p?.social_history ?? null,
      previous_treatment: p?.previous_treatment ?? null,
      patient_pronouns: p?.pronouns ?? null
    };
  });
  res.json({ sessions: enriched, patientMap });
});

// --- Templates ---
app.get("/api/v1/fetch-default-template-ext", auth, (req, res) => {
  const userId = String(req.query.userId || "");
  if (!userId) return res.status(400).json({ error: "userId parameter required" });
  const list = templates.filter(t => t.userId === userId).map(t => ({ id: t.id, title: t.title, type: t.type }));
  res.json({ success: true, data: list });
});

// --- Recording / Upload ---
app.post("/api/v1/upload-session", auth, (req, res) => {
  const { patientId, userId, patientName, status, startTime, templateId } = req.body ?? {};
  if (!patientId || !userId || !patientName) return res.status(400).json({ error: "patientId, userId, patientName required" });
  const sess: Session = {
    id: `session_${randomUUID()}`,
    user_id: userId,
    patient_id: patientId,
    patient_name: patientName,
    session_title: "New Recording Session",
    session_summary: null,
    transcript_status: "pending",
    transcript: null,
    status: status || "recording",
    date: new Date().toISOString().slice(0,10),
    start_time: startTime || new Date().toISOString(),
    end_time: null,
    duration: null,
    template_id: templateId,
    clinical_notes: []
  };
  sessions.push(sess);
  res.status(201).json({ id: sess.id });
});

app.post("/api/v1/get-presigned-url", auth, (req, res) => {
  const { sessionId, chunkNumber, mimeType } = req.body ?? {};
  if (!sessionId || chunkNumber === undefined) return res.status(400).json({ error: "sessionId and chunkNumber required" });
  const p = presigned(sessionId, Number(chunkNumber));
  audioChunks[sessionId] ||= {};
  audioChunks[sessionId][String(chunkNumber)] = { uploaded: false, mimeType: mimeType ?? "audio/wav", timestamp: new Date().toISOString() };
  res.json(p);
});

// Raw binary upload
app.put("/api/upload-chunk/:sessionId/:chunkNumber", async (req, res) => {
  const { sessionId, chunkNumber } = req.params;
  const filename = `${sessionId}_chunk_${chunkNumber}.wav`;
  const filepath = path.join(uploadsDir, filename);
  try {
    const buf = Buffer.from(req.body as any);
    await fs.writeFile(filepath, buf);
    audioChunks[sessionId] ||= {};
    audioChunks[sessionId][String(chunkNumber)] ||= {};
    audioChunks[sessionId][String(chunkNumber)].uploaded = true;
    audioChunks[sessionId][String(chunkNumber)].filepath = filepath;
    res.status(200).send("");
  } catch (e: any) {
    res.status(500).json({ error: "Upload failed", details: e.message });
  }
});

app.post("/api/v1/notify-chunk-uploaded", auth, (req, res) => {
  const { sessionId, chunkNumber, isLast } = req.body ?? {};
  if (!sessionId || chunkNumber === undefined) return res.status(400).json({ error: "sessionId and chunkNumber required" });
  audioChunks[sessionId] ||= {};
  audioChunks[sessionId][String(chunkNumber)] ||= {};
  audioChunks[sessionId][String(chunkNumber)].notified = true;
  if (isLast) {
    const s = sessions.find(x => x.id === sessionId);
    if (s) {
      s.status = "processing";
      s.end_time = new Date().toISOString();
      setTimeout(() => {
        s.status = "completed";
        s.transcript_status = "completed";
        s.transcript = "This is a mock transcript generated for demo purposes.";
        s.session_summary = "Mock session summary.";
      }, 2000);
    }
  }
  res.json({});
});

// Debug endpoints
app.get("/api/debug/all-data", (_req, res) => {
  res.json({
    users: users.length,
    patients: patients.length,
    sessions: sessions.length,
    templates: templates.length,
    audioChunks: Object.keys(audioChunks).length
  });
});

app.get("/api/debug/chunks/:sessionId", (req, res) => {
  res.json(audioChunks[req.params.sessionId] || {});
});

// 404
app.use("*", (req, res) => {
  res.status(404).json({ error: "Not found", details: `Endpoint ${req.method} ${req.originalUrl} not found`, availableEndpoints: "/api/docs" });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 MediNote Mock API (TS) running on :${PORT}`);
  console.log(`📚 Docs: http://localhost:${PORT}/api/docs`);
});
