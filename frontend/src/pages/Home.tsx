

import React from 'react';
import ChatWindow from '../components/ChatWindow';

const Home: React.FC = () => {
  return (
    <div>
      <main className="chat-section">
        <ChatWindow />
      </main>
    </div>
  );
};

export default Home;