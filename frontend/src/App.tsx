import './App.css'
import { useAuth } from "react-oidc-context";
import AppRouter from "./AppRouter";

function App() {
  const auth = useAuth();

  const signOutRedirect = () => {
    const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID;
    const logoutUri = window.location.origin;
    const cognitoDomain = `https://${import.meta.env.VITE_COGNITO_DOMAIN}`;
    window.location.href = `${cognitoDomain}/logout?client_id=${clientId}&logout_uri=${encodeURIComponent(logoutUri)}`;
  };

  if (auth.isLoading) {
    return <div>Loading...</div>;
  }

  if (auth.error) {
    return <div>Encountering error... {auth.error.message}</div>;
  }

  if (auth.isAuthenticated) {
    console.log("User profile:", auth.user?.profile);
    return (
      <div>
                
        {/* Load the rest of your app here */}
        <AppRouter />
        <div>
          Hello, {auth.user?.profile.email} |
          <a href="#" onClick={() => auth.removeUser()}> Sign Out</a>
          </div>
      </div>
    );
  }

  return (
    <div className="container">
      <button onClick={() => auth.signinRedirect()}>Sign in</button>
      <button onClick={() => signOutRedirect()}>Sign out</button>
    </div>
  );
}

export default App;