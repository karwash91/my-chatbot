resource "aws_sqs_queue" "ingest_queue" {
  name = "my-chatbot-ingest-queue"

  tags = {
    Project = "my-chatbot"
  }
}