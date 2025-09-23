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
        <div className="container header-bar">
          <span className="greeting">Hello, {auth.user?.profile.email}</span>
          <button className="signout-btn" onClick={() => auth.removeUser()}>Sign Out</button>
        </div>
        <hr className="divider" />
        <AppRouter />
        <div className="container">
          <p className="caption-text">Need help? Contact <a href='mailto:example@example.com'>example@example.com</a> | <a href='https://github.com/karwash91/my-chatbot' target='_blank'>GitHub</a></p>
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