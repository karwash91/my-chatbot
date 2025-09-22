import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { AuthProvider } from "react-oidc-context";

const cognitoAuthConfig = {
  authority: import.meta.env.VITE_COGNITO_ISSUER, // <-- use issuer here
  client_id: import.meta.env.VITE_COGNITO_CLIENT_ID,
  redirect_uri: window.location.origin, // dynamic based on where app runs
  response_type: "code",
  scope: "aws.cognito.signin.user.admin email openid phone profile",
};


createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <AuthProvider {...cognitoAuthConfig}>
      <App />
    </AuthProvider>
  </StrictMode>
)
