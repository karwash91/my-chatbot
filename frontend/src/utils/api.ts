// src/utils/api.ts
import axios from "axios";
import { API_BASE_URL } from "./config";
import { toast } from "react-hot-toast";

// Helper: create axios instance
const api = axios.create({
  baseURL: API_BASE_URL,
  headers: { "Content-Type": "application/json" },
});

// --- Upload a document ---
// Sends a POST request to upload a document with filename and content
export async function uploadDoc(filename: string, content: string) {
  try {
    const body = { filename, content };
    const res = await api.post("/upload", body);
    return res.data;
  } catch (error) {
    toast.error("Error uploading document");
    throw new Error("Failed to upload document");
  }
}

// --- Chat with the bot ---
// Sends a POST request with a query to chat endpoint and returns the response
export async function sendChat(query: string) {
  try {
    const body = { query };
    const res = await api.post("/chat", body);
    return res.data;
  } catch (error) {
    toast.error("Error sending chat query");
    throw new Error("Failed to send chat query");
  }
}

// --- Fetch documents / context ---
// Sends a GET request to fetch documents or context data
export async function fetchDocs() {
  try {
    const res = await api.get("/fetch");
    return res.data;
  } catch (error) {
    toast.error("Error fetching documents");
    throw new Error("Failed to fetch documents");
  }
}

export default { uploadDoc, sendChat, fetchDocs };