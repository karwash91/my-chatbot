import './App.css'
import { useAuth } from "react-oidc-context";
import AppRouter from "./AppRouter";
import { MdLogout } from "react-icons/md";

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
        <div>
          <h1 className="app-title">My Chatbot</h1>
        </div>
        <div className="spacer"/>
        <div className="container-centered header-bar">
          <span className="greeting">  Hello, {String(auth.user?.profile["cognito:username"] ?? "")}!</span>
          <button className="signout-btn" onClick={() => auth.removeUser()}>Sign Out < MdLogout /></button>
        </div>
        <div className="spacer"/>
        <hr className="divider" />
        <div className="spacer"/>
        <AppRouter />
        <div className="spacer"/>
        <div className="container-centered">
          <p className="caption-text">Need help? Contact <a href='mailto:example@example.com'>example@example.com</a> | <a href='https://github.com/karwash91/my-chatbot' target='_blank'>GitHub</a></p>
        </div>
      </div>
    );
  }

  return (
    <div className="container-centered">
      <button onClick={() => auth.signinRedirect()}>Sign In</button>
    </div>
  );
}

export default App;