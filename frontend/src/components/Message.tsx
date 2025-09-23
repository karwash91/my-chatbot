

// Message.tsx
// A functional React component for displaying a chat message.
// Props:
//   sender: "user" | "bot" - determines the message style
//   text: string - the message content

import React from 'react';

type MessageProps = {
  sender: 'user' | 'bot';
  text: string;
};

const Message: React.FC<MessageProps> = ({ sender, text }) => {
  return (
    <div className={`message ${sender}`}>
      <div>{text}</div>
    </div>
  );
};

export default Message;