import './App.css'
import { useAuth } from "react-oidc-context";
import AppRouter from "./AppRouter";

function App() {
  const auth = useAuth();

  if (auth.isLoading) {
    return <div className="loading">Loading...</div>;
  }

  if (auth.error) {
    return <div className="error">Encountering error... {auth.error.message}</div>;
  }

  if (auth.isAuthenticated) {
    console.log("User profile:", auth.user?.profile);
    return (
      <div>
        {/* Load the rest of your app here */}
        <AppRouter />
        <div className="auth-bar">
          Hello, {auth.user?.profile.email}
          <button onClick={() => auth.removeUser()}>Sign Out</button>
        </div>
      </div>
    );
  }

  return (
    <div className="container">
      <button onClick={() => auth.signinRedirect()}>Sign In</button>
    </div>
  );
}

export default App;