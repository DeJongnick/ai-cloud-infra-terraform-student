terraform {
  backend "gcs" {
    bucket = "advanced-cloud-ai-tfstate"
    prefix = "team3" # team1, team2, team3 ou team4
  }
}
