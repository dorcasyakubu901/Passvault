;; Emergency Travel Assistance System
;; Provides expedited processing for travelers in emergency situations

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_EMERGENCY_NOT_FOUND (err u301))
(define-constant ERR_EMERGENCY_ALREADY_PROCESSED (err u302))
(define-constant ERR_INVALID_EMERGENCY_TYPE (err u303))
(define-constant ERR_DOCUMENTATION_INSUFFICIENT (err u304))
(define-constant ERR_EMERGENCY_EXPIRED (err u305))
(define-constant ERR_APPROVAL_ALREADY_GRANTED (err u306))
(define-constant ERR_INVALID_URGENCY_LEVEL (err u307))
(define-constant ERR_EMERGENCY_ALREADY_EXISTS (err u308))

(define-data-var next-emergency-id uint u1)
(define-data-var emergency-processing-fee uint u50000) ;; Reduced fee for emergencies
(define-data-var max-emergency-duration uint u720) ;; 12 hours max validity

;; Store emergency travel requests
(define-map emergency-requests
    uint
    {
        emergency-id: uint,
        requester: principal,
        emergency-type: (string-ascii 30), ;; "medical", "family", "business", "diplomatic"
        urgency-level: uint, ;; 1-5 scale (5=most urgent)
        description: (string-ascii 500),
        supporting-documents: (list 5 (buff 32)), ;; Hash of supporting docs
        emergency-contact: (string-ascii 100),
        requested-destination: (string-ascii 50),
        estimated-duration: uint,
        request-date: uint,
        status: (string-ascii 20), ;; "pending", "approved", "denied", "expired"
        processing-authority: (optional principal),
        approval-date: (optional uint),
        emergency-voucher-id: (optional uint)
    }
)

;; Track emergency contacts and verification
(define-map emergency-contacts
    { contact-id: (string-ascii 100) }
    {
        contact-type: (string-ascii 30), ;; "hospital", "embassy", "family", "employer"
        verified: bool,
        verification-authority: (optional principal),
        verification-date: (optional uint),
        contact-details: (string-ascii 200),
        emergency-protocols: (string-ascii 300)
    }
)

;; Store emergency processing statistics
(define-map emergency-stats
    { emergency-type: (string-ascii 30) }
    {
        total-requests: uint,
        approved-requests: uint,
        denied-requests: uint,
        average-processing-time: uint,
        success-rate: uint,
        last-request-date: uint
    }
)

;; Track authority emergency processing capabilities
(define-map authority-emergency-permissions
    principal
    {
        can-process-medical: bool,
        can-process-family: bool,
        can-process-business: bool,
        can-process-diplomatic: bool,
        max-urgency-level: uint,
        processing-fee-waiver: uint, ;; Percentage waiver (0-100)
        fast-track-enabled: bool
    }
)

;; Submit an emergency travel assistance request
(define-public (submit-emergency-request
    (emergency-type (string-ascii 30))
    (urgency-level uint)
    (description (string-ascii 500))
    (supporting-documents (list 5 (buff 32)))
    (emergency-contact (string-ascii 100))
    (destination (string-ascii 50))
    (estimated-duration uint))
    (let
        (
            (emergency-id (var-get next-emergency-id))
            (processing-fee (var-get emergency-processing-fee))
        )
        (asserts! (and (<= urgency-level u5) (>= urgency-level u1)) ERR_INVALID_URGENCY_LEVEL)
        (asserts! (<= estimated-duration (var-get max-emergency-duration)) ERR_EMERGENCY_EXPIRED)
        (asserts! (>= (stx-get-balance tx-sender) processing-fee) ERR_UNAUTHORIZED)
        
        ;; Charge reduced processing fee
        (try! (stx-transfer? processing-fee tx-sender CONTRACT_OWNER))
        
        (map-set emergency-requests emergency-id {
            emergency-id: emergency-id,
            requester: tx-sender,
            emergency-type: emergency-type,
            urgency-level: urgency-level,
            description: description,
            supporting-documents: supporting-documents,
            emergency-contact: emergency-contact,
            requested-destination: destination,
            estimated-duration: estimated-duration,
            request-date: stacks-block-height,
            status: "pending",
            processing-authority: none,
            approval-date: none,
            emergency-voucher-id: none
        })
        
        (unwrap-panic (update-emergency-stats emergency-type "request"))
        (var-set next-emergency-id (+ emergency-id u1))
        (ok emergency-id)
    )
)

;; Process emergency request (Authority only)
(define-public (process-emergency-request
    (emergency-id uint)
    (approved bool)
    (processing-notes (string-ascii 300)))
    (let
        (
            (request-info (unwrap! (map-get? emergency-requests emergency-id) ERR_EMERGENCY_NOT_FOUND))
            (authority-perms (map-get? authority-emergency-permissions tx-sender))
        )
        (asserts! (is-some authority-perms) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status request-info) "pending") ERR_EMERGENCY_ALREADY_PROCESSED)
        
        (let 
            (
                (perms (unwrap-panic authority-perms))
                (can-process (verify-authority-permissions (get emergency-type request-info) (get urgency-level request-info) perms))
            )
            (asserts! can-process ERR_UNAUTHORIZED)
            
            (if approved
                (begin
                    ;; Create emergency voucher with expedited processing
                    (let ((emergency-voucher-id (unwrap-panic (create-emergency-voucher request-info))))
                        (map-set emergency-requests emergency-id
                            (merge request-info {
                                status: "approved",
                                processing-authority: (some tx-sender),
                                approval-date: (some stacks-block-height),
                                emergency-voucher-id: (some emergency-voucher-id)
                            }))
                        (unwrap-panic (update-emergency-stats (get emergency-type request-info) "approved"))
                    )
                )
                (begin
                    (map-set emergency-requests emergency-id
                        (merge request-info {
                            status: "denied",
                            processing-authority: (some tx-sender),
                            approval-date: (some stacks-block-height)
                        }))
                    (unwrap-panic (update-emergency-stats (get emergency-type request-info) "denied"))
                )
            )
            (ok approved)
        )
    )
)

;; Grant emergency processing permissions to authorities
(define-public (grant-emergency-permissions
    (authority principal)
    (medical bool)
    (family bool)
    (business bool)
    (diplomatic bool)
    (max-urgency uint)
    (fee-waiver-percent uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= fee-waiver-percent u100) ERR_INVALID_URGENCY_LEVEL)
        (asserts! (<= max-urgency u5) ERR_INVALID_URGENCY_LEVEL)
        
        (map-set authority-emergency-permissions authority {
            can-process-medical: medical,
            can-process-family: family,
            can-process-business: business,
            can-process-diplomatic: diplomatic,
            max-urgency-level: max-urgency,
            processing-fee-waiver: fee-waiver-percent,
            fast-track-enabled: true
        })
        (ok true)
    )
)

;; Register trusted emergency contact
(define-public (register-emergency-contact
    (contact-id (string-ascii 100))
    (contact-type (string-ascii 30))
    (contact-details (string-ascii 200))
    (protocols (string-ascii 300)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (map-set emergency-contacts { contact-id: contact-id } {
            contact-type: contact-type,
            verified: true,
            verification-authority: (some tx-sender),
            verification-date: (some stacks-block-height),
            contact-details: contact-details,
            emergency-protocols: protocols
        })
        (ok true)
    )
)

;; Private function to verify authority can process emergency type
(define-private (verify-authority-permissions 
    (emergency-type (string-ascii 30)) 
    (urgency-level uint) 
    (permissions {can-process-medical: bool, can-process-family: bool, can-process-business: bool, can-process-diplomatic: bool, max-urgency-level: uint, processing-fee-waiver: uint, fast-track-enabled: bool}))
    (let
        (
            (type-permission (if (is-eq emergency-type "medical") (get can-process-medical permissions)
                               (if (is-eq emergency-type "family") (get can-process-family permissions)
                                 (if (is-eq emergency-type "business") (get can-process-business permissions)
                                   (if (is-eq emergency-type "diplomatic") (get can-process-diplomatic permissions)
                                     false)))))
            (urgency-permission (<= urgency-level (get max-urgency-level permissions)))
        )
        (and type-permission urgency-permission (get fast-track-enabled permissions))
    )
)

;; Create emergency voucher with expedited processing
(define-private (create-emergency-voucher (request {emergency-id: uint, requester: principal, emergency-type: (string-ascii 30), urgency-level: uint, description: (string-ascii 500), supporting-documents: (list 5 (buff 32)), emergency-contact: (string-ascii 100), requested-destination: (string-ascii 50), estimated-duration: uint, request-date: uint, status: (string-ascii 20), processing-authority: (optional principal), approval-date: (optional uint), emergency-voucher-id: (optional uint)}))
    (let
        (
            (emergency-voucher-type "EMERGENCY")
            (expedited-duration (get estimated-duration request))
            (destination (get requested-destination request))
        )
        ;; Create special emergency voucher via main contract call
        (contract-call? .Passvault issue-voucher emergency-voucher-type "EMERGENCY" destination)
    )
)

;; Update emergency statistics
(define-private (update-emergency-stats (emergency-type (string-ascii 30)) (action (string-ascii 10)))
    (let
        (
            (current-stats (default-to 
                {
                    total-requests: u0,
                    approved-requests: u0,
                    denied-requests: u0,
                    average-processing-time: u1,
                    success-rate: u0,
                    last-request-date: u0
                }
                (map-get? emergency-stats { emergency-type: emergency-type })
            ))
        )
        (let
            (
                (new-total (if (is-eq action "request") (+ (get total-requests current-stats) u1) (get total-requests current-stats)))
                (new-approved (if (is-eq action "approved") (+ (get approved-requests current-stats) u1) (get approved-requests current-stats)))
                (new-denied (if (is-eq action "denied") (+ (get denied-requests current-stats) u1) (get denied-requests current-stats)))
                (new-success-rate (if (> new-total u0) (/ (* new-approved u100) new-total) u0))
            )
            (map-set emergency-stats { emergency-type: emergency-type }
                (merge current-stats {
                    total-requests: new-total,
                    approved-requests: new-approved,
                    denied-requests: new-denied,
                    success-rate: new-success-rate,
                    last-request-date: stacks-block-height
                }))
        )
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-emergency-request (emergency-id uint))
    (map-get? emergency-requests emergency-id)
)

(define-read-only (get-emergency-contact-info (contact-id (string-ascii 100)))
    (map-get? emergency-contacts { contact-id: contact-id })
)

(define-read-only (get-authority-emergency-permissions (authority principal))
    (map-get? authority-emergency-permissions authority)
)

(define-read-only (get-emergency-statistics (emergency-type (string-ascii 30)))
    (map-get? emergency-stats { emergency-type: emergency-type })
)

(define-read-only (calculate-emergency-priority-score (emergency-id uint))
    (match (map-get? emergency-requests emergency-id)
        request-data (let
            (
                (urgency-score (* (get urgency-level request-data) u20))
                (time-penalty (/ (- stacks-block-height (get request-date request-data)) u10))
                (doc-bonus (if (> (len (get supporting-documents request-data)) u2) u10 u0))
            )
            (+ urgency-score doc-bonus (if (> time-penalty urgency-score) u0 (- urgency-score time-penalty)))
        )
        u0
    )
)

(define-read-only (is-emergency-contact-verified (contact-id (string-ascii 100)))
    (match (map-get? emergency-contacts { contact-id: contact-id })
        contact-data (get verified contact-data)
        false
    )
)

(define-read-only (get-emergency-processing-metrics)
    {
        total-emergency-requests: (var-get next-emergency-id),
        processing-fee: (var-get emergency-processing-fee),
        max-duration: (var-get max-emergency-duration),
        average-processing-time: u2, ;; Blocks - simplified for demo
        success-rate: u85 ;; Percentage - simplified for demo
    }
)

(define-read-only (get-next-emergency-id)
    (var-get next-emergency-id)
)
