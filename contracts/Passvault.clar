;; title: Passvault
;; version: 1.0.0
;; summary: Border Crossing Voucher System - Verified smart contract travel passes
;; description: A decentralized system for managing border crossing vouchers with verification and expiration

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))  
(define-constant ERR_VOUCHER_NOT_FOUND (err u101))
(define-constant ERR_VOUCHER_EXPIRED (err u102))
(define-constant ERR_VOUCHER_ALREADY_USED (err u103))
(define-constant ERR_INVALID_VOUCHER_TYPE (err u104))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u105))
(define-constant ERR_BORDER_NOT_REGISTERED (err u106))
(define-constant ERR_ALREADY_VERIFIED (err u107))
(define-constant ERR_INVALID_EXPIRY (err u108))

(define-data-var next-voucher-id uint u1)
(define-data-var total-vouchers-issued uint u0)
(define-data-var total-vouchers-used uint u0)
(define-data-var border-crossing-fee uint u1000000)

(define-map vouchers
  { voucher-id: uint }
  {
    owner: principal,
    voucher-type: (string-ascii 20),
    from-border: (string-ascii 50),
    to-border: (string-ascii 50),
    issue-height: uint,
    expiry-height: uint,
    is-used: bool,
    is-verified: bool,
    verification-authority: (optional principal),
    usage-timestamp: (optional uint)
  }
)

(define-map border-authorities
  { border-code: (string-ascii 10) }
  {
    authority: principal,
    border-name: (string-ascii 50),
    is-active: bool
  }
)

(define-map user-voucher-count
  { user: principal }
  { count: uint }
)

(define-map voucher-types
  { type-name: (string-ascii 20) }
  {
    base-fee: uint,
    validity-blocks: uint,
    is-active: bool
  }
)

(define-public (initialize-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (try! (add-voucher-type "TOURIST" u500000 u1440))
    (try! (add-voucher-type "BUSINESS" u750000 u2880))
    (try! (add-voucher-type "TRANSIT" u250000 u720))
    (try! (add-voucher-type "DIPLOMATIC" u0 u4320))
    (ok true)
  )
)

(define-public (add-voucher-type (type-name (string-ascii 20)) (base-fee uint) (validity-blocks uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set voucher-types 
      { type-name: type-name }
      {
        base-fee: base-fee,
        validity-blocks: validity-blocks,
        is-active: true
      }
    )
    (ok true)
  )
)

(define-public (register-border-authority (border-code (string-ascii 10)) (authority principal) (border-name (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (map-set border-authorities
      { border-code: border-code }
      {
        authority: authority,
        border-name: border-name,
        is-active: true
      }
    )
    (ok true)
  )
)

(define-public (issue-voucher (voucher-type (string-ascii 20)) (from-border (string-ascii 50)) (to-border (string-ascii 50)))
  (let
    (
      (voucher-id (var-get next-voucher-id))
      (voucher-info (unwrap! (map-get? voucher-types { type-name: voucher-type }) ERR_INVALID_VOUCHER_TYPE))
      (current-height stacks-block-height)
      (expiry-height (+ current-height (get validity-blocks voucher-info)))
      (fee (get base-fee voucher-info))
    )
    (asserts! (>= (stx-get-balance tx-sender) fee) ERR_INSUFFICIENT_PAYMENT)
    (asserts! (get is-active voucher-info) ERR_INVALID_VOUCHER_TYPE)
    
    (if (> fee u0)
      (try! (stx-transfer? fee tx-sender CONTRACT_OWNER))
      true
    )
    
    (map-set vouchers
      { voucher-id: voucher-id }
      {
        owner: tx-sender,
        voucher-type: voucher-type,
        from-border: from-border,
        to-border: to-border,
        issue-height: current-height,
        expiry-height: expiry-height,
        is-used: false,
        is-verified: false,
        verification-authority: none,
        usage-timestamp: none
      }
    )
    
    (map-set user-voucher-count
      { user: tx-sender }
      { count: (+ (get-user-voucher-count tx-sender) u1) }
    )
    
    (var-set next-voucher-id (+ voucher-id u1))
    (var-set total-vouchers-issued (+ (var-get total-vouchers-issued) u1))
    
    (ok voucher-id)
  )
)

(define-public (verify-voucher (voucher-id uint) (border-code (string-ascii 10)))
  (let
    (
      (voucher (unwrap! (map-get? vouchers { voucher-id: voucher-id }) ERR_VOUCHER_NOT_FOUND))
      (border-auth (unwrap! (map-get? border-authorities { border-code: border-code }) ERR_BORDER_NOT_REGISTERED))
    )
    (asserts! (is-eq tx-sender (get authority border-auth)) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active border-auth) ERR_BORDER_NOT_REGISTERED)
    (asserts! (not (get is-verified voucher)) ERR_ALREADY_VERIFIED)
    (asserts! (< stacks-block-height (get expiry-height voucher)) ERR_VOUCHER_EXPIRED)
    (asserts! (not (get is-used voucher)) ERR_VOUCHER_ALREADY_USED)
    
    (map-set vouchers
      { voucher-id: voucher-id }
      (merge voucher { 
        is-verified: true,
        verification-authority: (some tx-sender)
      })
    )
    
    (ok true)
  )
)

(define-public (use-voucher (voucher-id uint) (border-code (string-ascii 10)))
  (let
    (
      (voucher (unwrap! (map-get? vouchers { voucher-id: voucher-id }) ERR_VOUCHER_NOT_FOUND))
      (border-auth (unwrap! (map-get? border-authorities { border-code: border-code }) ERR_BORDER_NOT_REGISTERED))
    )
    (asserts! (is-eq tx-sender (get authority border-auth)) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active border-auth) ERR_BORDER_NOT_REGISTERED)
    (asserts! (get is-verified voucher) ERR_NOT_AUTHORIZED)
    (asserts! (< stacks-block-height (get expiry-height voucher)) ERR_VOUCHER_EXPIRED)
    (asserts! (not (get is-used voucher)) ERR_VOUCHER_ALREADY_USED)
    
    (map-set vouchers
      { voucher-id: voucher-id }
      (merge voucher { 
        is-used: true,
        usage-timestamp: (some stacks-block-height)
      })
    )
    
    (var-set total-vouchers-used (+ (var-get total-vouchers-used) u1))
    
    (ok true)
  )
)

(define-public (extend-voucher (voucher-id uint) (additional-blocks uint))
  (let
    (
      (voucher (unwrap! (map-get? vouchers { voucher-id: voucher-id }) ERR_VOUCHER_NOT_FOUND))
      (extension-fee (* additional-blocks u100))
    )
    (asserts! (is-eq tx-sender (get owner voucher)) ERR_NOT_AUTHORIZED)
    (asserts! (not (get is-used voucher)) ERR_VOUCHER_ALREADY_USED)
    (asserts! (>= (stx-get-balance tx-sender) extension-fee) ERR_INSUFFICIENT_PAYMENT)
    (asserts! (> additional-blocks u0) ERR_INVALID_EXPIRY)
    
    (try! (stx-transfer? extension-fee tx-sender CONTRACT_OWNER))
    
    (map-set vouchers
      { voucher-id: voucher-id }
      (merge voucher { 
        expiry-height: (+ (get expiry-height voucher) additional-blocks)
      })
    )
    
    (ok true)
  )
)

(define-public (set-border-crossing-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set border-crossing-fee new-fee)
    (ok true)
  )
)

(define-read-only (get-voucher (voucher-id uint))
  (map-get? vouchers { voucher-id: voucher-id })
)

(define-read-only (get-border-authority (border-code (string-ascii 10)))
  (map-get? border-authorities { border-code: border-code })
)

(define-read-only (get-voucher-type (type-name (string-ascii 20)))
  (map-get? voucher-types { type-name: type-name })
)

(define-read-only (get-user-voucher-count (user principal))
  (default-to u0 (get count (map-get? user-voucher-count { user: user })))
)

(define-read-only (get-contract-stats)
  {
    total-issued: (var-get total-vouchers-issued),
    total-used: (var-get total-vouchers-used),
    next-voucher-id: (var-get next-voucher-id),
    border-crossing-fee: (var-get border-crossing-fee)
  }
)

(define-read-only (is-voucher-valid (voucher-id uint))
  (let
    (
      (voucher (unwrap! (map-get? vouchers { voucher-id: voucher-id }) (ok false)))
    )
    (ok (and 
      (not (get is-used voucher))
      (get is-verified voucher)
      (< stacks-block-height (get expiry-height voucher))
    ))
  )
)

(define-read-only (get-voucher-status (voucher-id uint))
  (let
    (
      (voucher (unwrap! (map-get? vouchers { voucher-id: voucher-id }) (err "Voucher not found")))
      (current-height stacks-block-height)
    )
    (ok {
      is-expired: (>= current-height (get expiry-height voucher)),
      is-used: (get is-used voucher),
      is-verified: (get is-verified voucher),
      blocks-until-expiry: (if (< current-height (get expiry-height voucher))
                             (- (get expiry-height voucher) current-height)
                             u0)
    })
  )
)
