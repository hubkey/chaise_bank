use scrypto::prelude::*;
use std::cmp::{max, min};
use std::fmt;

blueprint! {
    struct Bank {
        vault: Vault,
        initial_fund_amount: Decimal,
        internal_admin: Vault,
        customer_badge: ResourceAddress,
        admin_badge: ResourceAddress,
        customers: HashMap<NonFungibleId, Customer>,
        defaults: Defaults,
    }

    impl Bank {
        pub fn new(initial_fund: Bucket) -> (ComponentAddress, Bucket) {
            let admin_badge = ResourceBuilder::new_fungible()
                .divisibility(DIVISIBILITY_NONE)
                .metadata("name", "Bank admin badge")
                .initial_supply(dec!("1"));

            let internal_admin = ResourceBuilder::new_fungible()
                .divisibility(DIVISIBILITY_NONE)
                .initial_supply(dec!("1"));

            let admin_badge_required = rule!(
                require(admin_badge.resource_address()) || require(internal_admin.resource_address()));

            let customer_badge = ResourceBuilder::new_non_fungible()
                .metadata("name", "Customer badge")
                .mintable(rule!(require(internal_admin.resource_address())), LOCKED)
                .burnable(admin_badge_required.clone(), LOCKED)
                .updateable_non_fungible_data(admin_badge_required.clone(), LOCKED)
                .no_initial_supply();

            let access_check = AccessRules::new()
                .method("set_customer_known", admin_badge_required.clone())
                .method("customer", admin_badge_required.clone())
                .default(rule!(allow_all));
            let vault = Vault::with_bucket(initial_fund);

            let initial_fund_amount = vault.amount();

            let component = Self {
                vault,
                initial_fund_amount,
                internal_admin: Vault::with_bucket(internal_admin),
                customer_badge,
                admin_badge: admin_badge.resource_address(),
                customers: HashMap::new(),
                defaults: Defaults::new(dec!("0.01"), dec!("1000000"), dec!("0.05"), dec!("1000"))
            }
            .instantiate()
            .add_access_check(access_check)
            .globalize();

            (component, admin_badge)
        }

        pub fn customer_registration(&mut self, first_name: String, last_name: String) -> (Bucket, ResourceAddress) {

            let customer_registration = CustomerRegistration::new(first_name, last_name);

            let customer_id = NonFungibleId::random();

            let customer_badge = self.internal_admin.authorize(|| {
                let resource_manager = borrow_resource_manager!(self.customer_badge);
                resource_manager.mint_non_fungible(
                    &customer_id,
                    customer_registration
                )
            });

            let customer = Customer::new(&self.defaults);

            self.customers.insert(customer_id, customer);

            (customer_badge, self.customer_badge)
        }

        pub fn deposit(&mut self, customer_badge: Proof, amount: Decimal, mut funds: Bucket) -> Bucket {
            let customer_id = customer_badge.non_fungible::<CustomerRegistration>().id();

            match self.customers.get_mut(&customer_id) {
                Some(customer) => {
                    assert!(amount <= funds.amount(), "Insufficient funds");
                    assert!(amount > dec!("0"), "Amount must be greater than zero");
                    assert!(customer.known_since != None, "Unknown customer");

                    customer.account = customer.account.credit(amount);
                    self.vault.put(funds.take(amount));

                    info!("{:?}", customer);

                    funds
                },
                None => panic!("Customer not found")
            }
        }

        pub fn withdraw(&mut self, customer_badge: Proof, amount: Decimal) -> Bucket {
            let customer_id = customer_badge.non_fungible::<CustomerRegistration>().id();

            match self.customers.get_mut(&customer_id) {
                Some(customer) => {
                    assert!(amount <= self.vault.amount(), "Insufficient funds");
                    assert!(amount > dec!("0"), "Amount must be greater than zero");
                    assert!(customer.known_since != None, "Unknown customer");

                    customer.account = customer.account.debit(amount);
                    
                    info!("{:?}", customer);

                    self.vault.take(amount)
                },
                None => panic!("Customer not found")
            }
        }

        pub fn customer(&mut self, customer_id: NonFungibleId) -> String {
            match self.customers.get(&customer_id) {
                Some(customer) => format!("{:?}", customer),
                None => panic!("Customer not found")
            }
        }

        pub fn set_customer_known(&mut self, customer_id: NonFungibleId) {
            match self.customers.get_mut(&customer_id) {
                Some(customer) if customer.known_since != None => panic!("Customer already known"),
                Some(customer) => customer.known_since = Some(Runtime::current_epoch()),
                None => panic!("Customer not found")
            }
        }
    }
}

#[derive(Debug, TypeId, Encode, Decode, Describe, PartialEq, Eq)]
pub struct Balance {
    pub balance: Decimal,
    pub limit: Decimal,
    pub interest_rate: Decimal,
    pub last_update: u64,
}

impl Balance {
    fn new(interest_rate: Decimal, limit: Decimal) -> Balance {
        Balance {
            balance: dec!("0"),
            limit,
            interest_rate,
            last_update: Runtime::current_epoch(),
        }
    }

    pub fn new_balance(&self, new_balance: Decimal) -> Balance {
        let interest = self.balance * self.interest_rate * self.elapsed();
        let balance = interest + new_balance;

        assert!(balance < self.limit, "Limit reached");

        info!("Elapsed = {} ({} - {})", self.elapsed(), Runtime::current_epoch(), self.last_update);
        info!("Interest = {} ({} * {} * {})", interest, self.balance, self.interest_rate, self.elapsed());

        Balance {
            balance,
            last_update: Runtime::current_epoch(),
            ..*self
        }
    }

    pub fn elapsed(&self) -> u64 {
        Runtime::current_epoch() - self.last_update
    }
}

#[derive(TypeId, Encode, Decode, Describe, PartialEq, Eq)]
pub struct BankAccount {
    pub debit: Balance,
    pub credit: Balance,
}

impl BankAccount {
    pub fn new(defaults: &Defaults) -> BankAccount {
        BankAccount {
            debit: Balance::new(defaults.debit_interest_rate, defaults.debit_limit),
            credit: Balance::new(defaults.credit_interest_rate, defaults.credit_limit),
        }
    }

    pub fn new_balance(&self, new_balance: Decimal) -> BankAccount {
        BankAccount {
            debit: self.debit.new_balance(max(new_balance, dec!("0"))),
            credit: self.credit.new_balance(min(new_balance, dec!("0")).abs())
        }
    }

    pub fn signed_balance(&self) -> Decimal {
        self.debit.balance - self.credit.balance
    }

    //TODO: change balance and return type below to enum (debit/credit) and overload operators
    pub fn balance(&self) -> Decimal {
        self.signed_balance().abs()
    }

    pub fn balance_type(&self) -> String {
        if self.signed_balance() <= dec!("0") {
            "CR".to_string()
        } else {
            "DR".to_string()
        }
    }

    pub fn credit(&self, amount: Decimal) -> BankAccount {
        BankAccount::new_balance(self, self.signed_balance() - amount)
    }

    pub fn debit(&self, amount: Decimal) -> BankAccount {
        BankAccount::new_balance(self, self.signed_balance() + amount)
    }
}

impl fmt::Debug for BankAccount {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{} {}", self.balance(), self.balance_type())
    }
}

#[derive(NonFungibleData)]
struct CustomerRegistration {
    first_name: String,
    last_name: String,
}

impl CustomerRegistration {
    fn new(mut first_name: String, mut last_name: String) -> CustomerRegistration {
        first_name = first_name.trim().to_string();
        last_name = last_name.trim().to_string();
        assert!(!&first_name.is_empty(), "First name is required");
        assert!(!&last_name.is_empty(), "Last name is required");

        CustomerRegistration {
            first_name,
            last_name,
        }
    }
}

#[derive(Debug, TypeId, Encode, Decode, Describe)]
struct Customer {
    known_since: Option<u64>,
    customer_since: u64,
    account: BankAccount,
}

impl Customer {
    fn new(defaults: &Defaults) -> Customer {
        Customer {
            known_since: None,
            customer_since: Runtime::current_epoch(),
            account: BankAccount::new(defaults),
        }
    }
}

#[derive(Debug, TypeId, Encode, Decode, Describe)]
pub struct Defaults {
    credit_interest_rate: Decimal,
    credit_limit: Decimal,
    debit_interest_rate: Decimal,
    debit_limit: Decimal,
}

impl Defaults {
    fn new(
        credit_interest_rate: Decimal,
        credit_limit: Decimal,
        debit_interest_rate: Decimal,
        debit_limit: Decimal,
    ) -> Defaults {
        Defaults {
            credit_interest_rate,
            credit_limit,
            debit_interest_rate,
            debit_limit,
        }
    }
}
