import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { AuthProvider } from "react-oidc-context";

const cognitoAuthConfig = {
  authority: "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_ZiX12vSIY",
  client_id: "g1uv4bha1k8p5hdvtsfu6kn4a",
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
