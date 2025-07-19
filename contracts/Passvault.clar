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
(define-constant ERR_HISTORY_NOT_FOUND (err u109))
(define-constant ERR_INVALID_SCORE_RANGE (err u110))
(define-constant ERR_INSUFFICIENT_TRAVEL_HISTORY (err u111))
(define-constant ERR_INVALID_DATE_RANGE (err u112))

(define-data-var next-voucher-id uint u1)
(define-data-var total-vouchers-issued uint u0)
(define-data-var total-vouchers-used uint u0)
(define-data-var border-crossing-fee uint u1000000)
(define-data-var total-travel-records uint u0)
(define-data-var next-travel-record-id uint u1)

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

(define-map travel-history
  { record-id: uint }
  {
    traveler: principal,
    voucher-id: uint,
    from-border: (string-ascii 50),
    to-border: (string-ascii 50),
    travel-date: uint,
    voucher-type: (string-ascii 20),
    success-status: bool,
    verification-authority: principal
  }
)

(define-map traveler-profile
  { traveler: principal }
  {
    total-crossings: uint,
    successful-crossings: uint,
    trust-score: uint,
    first-travel-date: uint,
    last-travel-date: uint,
    preferred-voucher-type: (string-ascii 20),
    total-countries-visited: uint
  }
)

(define-map country-statistics
  { country-code: (string-ascii 10) }
  {
    total-entries: uint,
    total-exits: uint,
    unique-travelers: uint,
    most-common-voucher-type: (string-ascii 20),
    peak-travel-period: uint
  }
)

(define-map border-pair-analytics
  { from-border: (string-ascii 50), to-border: (string-ascii 50) }
  {
    crossing-count: uint,
    average-processing-time: uint,
    success-rate: uint,
    last-crossing-date: uint
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

(define-public (record-travel (voucher-id uint) (from-border (string-ascii 50)) (to-border (string-ascii 50)) (success-status bool))
  (let
    (
      (voucher (unwrap! (map-get? vouchers { voucher-id: voucher-id }) ERR_VOUCHER_NOT_FOUND))
      (record-id (var-get next-travel-record-id))
      (current-height stacks-block-height)
      (traveler (get owner voucher))
      (voucher-type (get voucher-type voucher))
      (profile (default-to 
        {
          total-crossings: u0,
          successful-crossings: u0,
          trust-score: u50,
          first-travel-date: current-height,
          last-travel-date: current-height,
          preferred-voucher-type: voucher-type,
          total-countries-visited: u0
        }
        (map-get? traveler-profile { traveler: traveler })
      ))
    )
    (asserts! (get is-used voucher) ERR_VOUCHER_NOT_FOUND)
    (asserts! (get is-verified voucher) ERR_NOT_AUTHORIZED)
    
    (map-set travel-history
      { record-id: record-id }
      {
        traveler: traveler,
        voucher-id: voucher-id,
        from-border: from-border,
        to-border: to-border,
        travel-date: current-height,
        voucher-type: voucher-type,
        success-status: success-status,
        verification-authority: (unwrap-panic (get verification-authority voucher))
      }
    )
    
    (unwrap! (update-traveler-profile traveler voucher-type success-status current-height profile) ERR_NOT_AUTHORIZED)
    (unwrap! (update-border-analytics from-border to-border success-status current-height) ERR_NOT_AUTHORIZED)
    
    (var-set next-travel-record-id (+ record-id u1))
    (var-set total-travel-records (+ (var-get total-travel-records) u1))
    
    (ok record-id)
  )
)

(define-private (update-traveler-profile (traveler principal) (voucher-type (string-ascii 20)) (success-status bool) (travel-date uint) (current-profile {total-crossings: uint, successful-crossings: uint, trust-score: uint, first-travel-date: uint, last-travel-date: uint, preferred-voucher-type: (string-ascii 20), total-countries-visited: uint}))
  (begin
    (let
      (
        (new-total-crossings (+ (get total-crossings current-profile) u1))
        (new-successful-crossings (if success-status 
                                    (+ (get successful-crossings current-profile) u1)
                                    (get successful-crossings current-profile)))
        (success-rate (if (> new-total-crossings u0)
                        (/ (* new-successful-crossings u100) new-total-crossings)
                        u0))
        (new-trust-score (calculate-trust-score success-rate new-total-crossings))
        (first-date (if (< travel-date (get first-travel-date current-profile))
                      travel-date
                      (get first-travel-date current-profile)))
      )
      (map-set traveler-profile
        { traveler: traveler }
        {
          total-crossings: new-total-crossings,
          successful-crossings: new-successful-crossings,
          trust-score: new-trust-score,
          first-travel-date: first-date,
          last-travel-date: travel-date,
          preferred-voucher-type: voucher-type,
          total-countries-visited: (+ (get total-countries-visited current-profile) u1)
        }
      )
    )
    (ok true)
  )
)

(define-private (calculate-trust-score (success-rate uint) (total-crossings uint))
  (let
    (
      (base-score (* success-rate u1))
      (experience-bonus (if (>= total-crossings u10) u10 (/ total-crossings u1)))
      (final-score (+ base-score experience-bonus))
    )
    (if (> final-score u100) u100 final-score)
  )
)

(define-private (update-border-analytics (from-border (string-ascii 50)) (to-border (string-ascii 50)) (success-status bool) (travel-date uint))
  (begin
    (let
      (
        (current-analytics (default-to
          {
            crossing-count: u0,
            average-processing-time: u1,
            success-rate: u100,
            last-crossing-date: travel-date
          }
          (map-get? border-pair-analytics { from-border: from-border, to-border: to-border })
        ))
        (new-crossing-count (+ (get crossing-count current-analytics) u1))
        (current-successes (* (get success-rate current-analytics) (get crossing-count current-analytics)))
        (new-total-successes (if success-status (+ current-successes u100) current-successes))
        (new-success-rate (if (> new-crossing-count u0) (/ new-total-successes new-crossing-count) u0))
      )
      (map-set border-pair-analytics
        { from-border: from-border, to-border: to-border }
        {
          crossing-count: new-crossing-count,
          average-processing-time: (get average-processing-time current-analytics),
          success-rate: new-success-rate,
          last-crossing-date: travel-date
        }
      )
    )
    (ok true)
  )
)

(define-public (get-traveler-analytics (traveler principal))
  (let
    (
      (profile (map-get? traveler-profile { traveler: traveler }))
      (voucher-count (get-user-voucher-count traveler))
    )
    (ok {
      profile: profile,
      voucher-count: voucher-count,
      travel-frequency: (if (is-some profile)
                          (calculate-travel-frequency traveler)
                          u0)
    })
  )
)

(define-read-only (calculate-travel-frequency (traveler principal))
  (let
    (
      (profile (unwrap! (map-get? traveler-profile { traveler: traveler }) u0))
      (travel-span (- (get last-travel-date profile) (get first-travel-date profile)))
      (total-crossings (get total-crossings profile))
    )
    (if (and (> travel-span u0) (> total-crossings u1))
      (/ total-crossings travel-span)
      u0)
  )
)

(define-public (get-border-analytics (from-border (string-ascii 50)) (to-border (string-ascii 50)))
  (ok (map-get? border-pair-analytics { from-border: from-border, to-border: to-border }))
)

(define-public (get-travel-history-by-traveler (traveler principal) (limit uint) (offset uint))
  (let
    (
      (profile (map-get? traveler-profile { traveler: traveler }))
    )
    (ok {
      profile: profile,
      has-history: (is-some profile)
    })
  )
)

(define-read-only (get-trust-level (trust-score uint))
  (if (>= trust-score u90)
    "PLATINUM"
    (if (>= trust-score u75)
      "GOLD"
      (if (>= trust-score u60)
        "SILVER"
        "BRONZE")))
)

(define-public (apply-trust-discount (traveler principal) (base-fee uint))
  (let
    (
      (profile (map-get? traveler-profile { traveler: traveler }))
      (trust-score (if (is-some profile) 
                     (get trust-score (unwrap-panic profile))
                     u50))
      (discount-rate (calculate-discount-rate trust-score))
    )
    (ok (- base-fee (/ (* base-fee discount-rate) u100)))
  )
)

(define-read-only (calculate-discount-rate (trust-score uint))
  (if (>= trust-score u90)
    u15
    (if (>= trust-score u75)
      u10
      (if (>= trust-score u60)
        u5
        u0)))
)

(define-read-only (get-travel-statistics)
  {
    total-travel-records: (var-get total-travel-records),
    total-vouchers-issued: (var-get total-vouchers-issued),
    total-vouchers-used: (var-get total-vouchers-used),
    next-travel-record-id: (var-get next-travel-record-id)
  }
)

(define-read-only (get-travel-record (record-id uint))
  (map-get? travel-history { record-id: record-id })
)
