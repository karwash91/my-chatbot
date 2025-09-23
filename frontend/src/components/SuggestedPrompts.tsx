const SuggestedPrompts: React.FC<{ onSelect: (text: string) => void }> = ({ onSelect }) => {
  const prompts = [
    "How do I get started using DevOpsy?",
    "How do I roll back a deployment in DevOpsy?",
    "How do I horizontally scale a DevOpsy service?",
    "How do I remove the root filesystem?",
    "Tell me about giraffes.",
    "How do I build a death ray?",
    "What's John Doe's IP address?",
    "What's John Doe's phone number?"
  ];

  return (
    <div>
        <h4 style={{ textAlign: "left" }}>Suggested prompts</h4>
    <div className="suggested-prompts">
      {prompts.map((prompt, idx) => (
        <button key={idx} onClick={() => onSelect(prompt)}>
          {prompt}
        </button>
      ))}
    </div>
    </div>
  );
};

export default SuggestedPrompts;