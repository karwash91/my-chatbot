// src/utils/config.ts

// Read from .env (make sure to add VITE_ prefix for Vite to pick it up)
// Base URL for API requests
export const API_BASE_URL =
  import.meta.env.VITE_API_BASE_URL ||
  "https://yf6mptf887.execute-api.us-east-1.amazonaws.com/dev";

// Cognito User Pool ID for authentication
export const COGNITO_USER_POOL_ID = import.meta.env.VITE_COGNITO_USER_POOL_ID || "";

// Cognito Client ID for authentication
export const COGNITO_CLIENT_ID = import.meta.env.VITE_COGNITO_CLIENT_ID || "";

// AWS region for Cognito services
export const AWS_REGION = import.meta.env.VITE_AWS_REGION || "us-east-1";

// Cognito domain for hosted UI
export const COGNITO_DOMAIN = import.meta.env.VITE_COGNITO_DOMAIN || "";