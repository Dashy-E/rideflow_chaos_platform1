output "users_table_name" {
  value = aws_dynamodb_table.users.name
}

output "users_table_arn" {
  value = aws_dynamodb_table.users.arn
}

output "rides_table_name" {
  value = aws_dynamodb_table.rides.name
}

output "rides_table_arn" {
  value = aws_dynamodb_table.rides.arn
}
