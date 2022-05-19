use radix_engine::transaction::TransactionExecutor;
use radix_engine::model::{SignedTransaction, Receipt};
use scrypto::crypto::{EcdsaPrivateKey, EcdsaPublicKey};
use radix_engine::ledger::*;
use radix_engine::transaction::*;
use scrypto::prelude::*;

struct Account {
    public_key: EcdsaPublicKey,
    private_key: EcdsaPrivateKey,
    account: ComponentAddress,
}

impl From<(EcdsaPublicKey, EcdsaPrivateKey, ComponentAddress)> for Account {
    fn from(e: (EcdsaPublicKey, EcdsaPrivateKey, ComponentAddress)) -> Self {
        Account { public_key: e.0, private_key: e.1, account: e.2 }
    }
}

impl Clone for Account {
    fn clone(&self) -> Self {
        Account {
            public_key: self.public_key,
            private_key: EcdsaPrivateKey::from_bytes(&self.private_key.to_bytes()).unwrap(),
            account: self.account,
        }
    }
}

struct TestEnv<'a, L: SubstateStore> {
    executor: TransactionExecutor<'a, L>,
    bank: ComponentAddress,
    customer: Account,
}

impl<'a, L: SubstateStore> TestEnv<'a, L> {

    fn new(ledger: &'a mut L) -> Self {
        let mut executor = TransactionExecutor::new(ledger, false);
        let owner: Account = executor.new_account().into();
        let customer: Account = executor.new_account().into();
        let package = executor.publish_package(compile_package!()).unwrap();
        
        let new_bank_transaction = TransactionBuilder::new()
            .withdraw_from_account_by_amount(dec!("1000"), RADIX_TOKEN, owner.account)
            .take_from_worktop(RADIX_TOKEN, |builder, bucket_id| {
                builder.call_function(package, "Bank", "new", args![scrypto::resource::Bucket(bucket_id)])
            })
            .call_method_with_all_resources(owner.account, "deposit_batch")
            .build(executor.get_nonce([owner.public_key]))
            .sign([&owner.private_key]);
    
        let bank = executor
            .validate_and_execute(&new_bank_transaction).unwrap()
            .new_component_addresses[0];
    
        TestEnv {
            executor,
            bank,
            customer,
        }
    }

    fn execute_transaction(&mut self, transaction: &'a SignedTransaction) -> Receipt {
        self.executor.validate_and_execute(transaction).unwrap()
    }

    fn signed_transaction(&mut self, builder: &mut TransactionBuilder, account: Account) -> SignedTransaction {
        builder.call_method_with_all_resources(account.account, "deposit_batch")
            .build(self.executor.get_nonce([account.public_key]))
            .sign([&account.private_key])
    }
}

#[test]
fn customer_registration_receipt_is_ok() {
    let mut ledger = InMemorySubstateStore::with_bootstrap();
    let mut env = TestEnv::new(&mut ledger);
    
    let transaction = env.signed_transaction(TransactionBuilder::new().call_method(
        env.bank.clone(), "customer_registration", args!["Satoshi", "Nakamoto"]), env.customer.clone());

    let receipt = env.execute_transaction(&transaction);

    let (_bucket, _resource_address) = scrypto_decode::<(Bucket, ResourceAddress)>(&receipt.outputs[0].raw).unwrap();
    
    assert!(receipt.result.is_ok());
}
