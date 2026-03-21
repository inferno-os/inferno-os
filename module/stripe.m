Stripe: module {
	PATH:	con "/dis/lib/stripe.dis";

	init:	fn(apikey: string): string;

	# Create a payment intent
	# amount in smallest currency unit (cents for USD)
	createpayment:	fn(amount: int, currency: string, description: string): (string, string);
		# returns (payment_intent_id, error)

	# Get account balance
	balance:	fn(): (string, string);
		# returns (formatted balance string, error)

	# List recent charges
	recent:		fn(count: int): (string, string);
		# returns (formatted list, error)
};
