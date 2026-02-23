import boto3
import os

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    route_table_id = os.environ['ROUTE_TABLE_ID']
    
    try:
        # Drops the default route to the NAT Gateway
        ec2.delete_route(
            DestinationCidrBlock='0.0.0.0/0',
            RouteTableId=route_table_id
        )
        print(f"SUCCESS: Severed NAT Gateway route in {route_table_id}. Billing leak stopped.")
        return {"status": 200, "message": "NAT route deleted"}
    except Exception as e:
        print(f"FAILED: Could not delete route. Error: {str(e)}")
        raise e