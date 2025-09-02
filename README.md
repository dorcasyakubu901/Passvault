# 🛂 Passvault - Border Crossing Voucher System

A decentralized smart contract system for managing verified travel passes and border crossing vouchers on the Stacks blockchain.

## 🌟 Features

- 🎫 **Digital Vouchers**: Issue tamper-proof border crossing vouchers
- ✅ **Verification System**: Multi-authority voucher verification
- ⏰ **Expiration Management**: Time-based voucher validity
- 🏛️ **Authority Management**: Register border crossing authorities
- 📊 **Usage Tracking**: Monitor voucher issuance and usage statistics
- 💰 **Fee Management**: Configurable fees for different voucher types

## 🚀 Getting Started

### Prerequisites
- Clarinet installed
- Stacks wallet setup
- STX tokens for transaction fees

### Installation

1. Clone the repository:
```bash
git clone https://github.com/your-username/passvault.git
cd passvault
```

2. Install dependencies:
```bash
npm install
```

3. Deploy to testnet:
```bash
clarinet integrate
```

## 📋 Voucher Types

| Type | 🎫 Fee | ⏰ Validity | 📝 Description |
|------|--------|-------------|----------------|
| TOURIST | 0.5 STX | 1 day | Regular tourism vouchers |
| BUSINESS | 0.75 STX | 2 days | Business travel vouchers |
| TRANSIT | 0.25 STX | 12 hours | Transit/connecting flights |
| DIPLOMATIC | Free | 3 days | Diplomatic immunity vouchers |

## 🔧 Usage

### Initialize Contract
```clarity
(contract-call? .passvault initialize-contract)
```

### Issue a Voucher
```clarity
(contract-call? .passvault issue-voucher "TOURIST" "JFK-NYC" "LHR-LON")
```

### Verify Voucher (Authority only)
```clarity
(contract-call? .passvault verify-voucher u1 "JFK")
```

### Use Voucher at Border (Authority only)
```clarity
(contract-call? .passvault use-voucher u1 "LHR")
```

### Check Voucher Status
```clarity
(contract-call? .passvault get-voucher-status u1)
```

### Extend Voucher Validity
```clarity
(contract-call? .passvault extend-voucher u1 u720)
```

## 👥 Authority Management

### Register Border Authority
```clarity
(contract-call? .passvault register-border-authority "JFK" 'SP1ABC... "John F. Kennedy International Airport")
```

### Add New Voucher Type
```clarity
(contract-call? .passvault add-voucher-type "VIP" u1000000 u2880)
```

## 📖 Read-Only Functions

- `get-voucher`: Retrieve voucher details
- `get-border-authority`: Get authority information
- `get-voucher-type`: Get voucher type details
- `get-user-voucher-count`: Count user's vouchers
- `get-contract-stats`: Overall system statistics
- `is-voucher-valid`: Check if voucher is valid for use
- `get-voucher-status`: Get detailed voucher status

## 🔒 Security Features

- 🛡️ **Access Control**: Only authorized personnel can verify/use vouchers
- ⏳ **Time Validation**: Automatic expiration checking
- 🚫 **One-Time Use**: Prevents voucher reuse fraud
- 💳 **Fee Protection**: STX balance validation before operations

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

Test specific functions:
```bash
clarinet console
```

## 📊 Error Codes

| Code | Description |
|------|-------------|
| u100 | Not authorized |
| u101 | Voucher not found |
| u102 | Voucher expired |
| u103 | Voucher already used |
| u104 | Invalid voucher type |
| u105 | Insufficient payment |
| u106 | Border not registered |
| u107 | Already verified |
| u108 | Invalid expiry |

## 🤝 Contributing

1. Fork the project
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙋‍♂️ Support

For support and questions:
- 📧 Email: support@passvault.com
- 💬 Discord: [Join our server](https://discord.gg/passvault)
- 🐛 Issues: [GitHub Issues](https://github.com/your-username/passvault/issues)

