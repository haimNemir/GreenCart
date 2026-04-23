output "elastic_ips" {
  value = [for eip in aws_eip.app : eip.public_ip]
}

output "instance_ids" {
  value = [for inst in aws_instance.app : inst.id]
}

output "key_pair_name" {
  value = aws_key_pair.this.key_name
}
