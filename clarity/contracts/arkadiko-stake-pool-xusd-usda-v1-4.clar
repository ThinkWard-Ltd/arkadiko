;; @contract Stake Pool - Stake xUSD/USDA LP tokens
;; A fixed amount of rewards per block will be distributed across all stakers, according to their size in the pool
;; Rewards will be automatically staked before staking or unstaking. 
;; The cumm reward per stake represents the rewards over time, taking into account total staking volume over time
;; When total stake changes, the cumm reward per stake is increased accordingly.
;; @version 1.4

(use-trait stake-pool-trait .arkadiko-stake-pool-trait-v1.stake-pool-trait)
(use-trait sft-trait 'SP3K8BC0PPEVCV7NZ6QSRWPQ2JE9E5B6N3PA0KBR9.trait-semi-fungible.semi-fungible-trait)
(use-trait stake-registry-trait .arkadiko-stake-registry-trait-v1.stake-registry-trait)
(use-trait ft-trait .sip-010-trait-ft-standard.sip-010-trait)

;; Errors
(define-constant ERR-NOT-AUTHORIZED (err u18401))
(define-constant ERR-REWARDS-CALC (err u18001))
(define-constant ERR-WRONG-TOKEN (err u18002))
(define-constant ERR-INSUFFICIENT-STAKE (err u18003))
(define-constant ERR-WRONG-REGISTRY (err u18004))

(define-constant TOKEN-ID u1)

;; Variables
(define-data-var total-staked uint u0)
(define-data-var cumm-reward-per-stake uint u0)
(define-data-var last-reward-increase-block uint u0) 

;; ---------------------------------------------------------
;; Stake Functions
;; ---------------------------------------------------------

;; Keep track of total amount staked and last cumm reward per stake
(define-map stakes 
   { staker: principal } 
   {
      uamount: uint,  ;; micro diko amount staked
      cumm-reward-per-stake: uint
   }
)

(define-read-only (get-stake-of (staker principal))
  (default-to
    { uamount: u0, cumm-reward-per-stake: u0 }
    (map-get? stakes { staker: staker })
  )
)

;; Get stake info - amount staked
(define-read-only (get-stake-amount-of (staker principal))
  (get uamount (get-stake-of staker))
)

;; Get stake info - last rewards block
(define-read-only (get-stake-cumm-reward-per-stake-of (staker principal))
  (get cumm-reward-per-stake (get-stake-of staker))
)

;; Get variable total-staked
(define-read-only (get-total-staked)
  (var-get total-staked)
)

;; Get variable cumm-reward-per-stake
(define-read-only (get-cumm-reward-per-stake)
  (var-get cumm-reward-per-stake)
)

;; Get variable last-reward-increase-block
(define-read-only (get-last-reward-increase-block)
  (var-get last-reward-increase-block)
)

;; @desc stake tokens in the pool, used by stake-registry
;; @param registry-trait; current stake registry
;; @param token; token to stake
;; @param amount; amount of tokens to stake
;; @post uint; returns amount of tokens staked
(define-public (stake (registry-trait <stake-registry-trait>) (token <sft-trait>) (amount uint))
  (begin
    ;; Check given registry
    (asserts! (is-eq (contract-of registry-trait) (unwrap-panic (contract-call? .arkadiko-dao get-qualified-name-by-name "stake-registry"))) ERR-WRONG-REGISTRY)

    (asserts! (is-eq 'SP3K8BC0PPEVCV7NZ6QSRWPQ2JE9E5B6N3PA0KBR9.token-amm-swap-pool (contract-of token)) ERR-WRONG-TOKEN)

    ;; Save currrent cumm reward per stake
    (unwrap-panic (increase-cumm-reward-per-stake registry-trait))

    (let (
      (staker tx-sender)
      ;; Calculate new stake amount
      (stake-amount (get-stake-amount-of staker))
      (new-stake-amount (+ stake-amount amount))
    )
      ;; Claim all pending rewards for staker so we can set the new cumm-reward for this user
      (try! (claim-pending-rewards registry-trait))

      ;; Update total stake
      (var-set total-staked (+ (var-get total-staked) amount))

      ;; Update cumm reward per stake now that total is updated
      (unwrap-panic (increase-cumm-reward-per-stake registry-trait))

      ;; Transfer LP token to this contract
      (try! (contract-call? 'SP3K8BC0PPEVCV7NZ6QSRWPQ2JE9E5B6N3PA0KBR9.token-amm-swap-pool transfer TOKEN-ID amount staker (as-contract tx-sender)))

      ;; Update sender stake info
      (map-set stakes { staker: staker } { uamount: new-stake-amount, cumm-reward-per-stake: (var-get cumm-reward-per-stake) })

      (ok amount)
    )
  )
)

;; @desc unstake tokens in the pool, used by stake-registry
;; @param registry-trait; current stake registry
;; @param token; token to unstake
;; @param amount; amount of tokens to unstake
;; @post uint; returns amount of tokens unstaked
(define-public (unstake (registry-trait <stake-registry-trait>) (token <sft-trait>) (amount uint))
  (let (
    (staker tx-sender)

    ;; Staked amount of staker
    (stake-amount (get-stake-amount-of staker))
  )
    ;; Check given registry
    (asserts! (is-eq (contract-of registry-trait) (unwrap-panic (contract-call? .arkadiko-dao get-qualified-name-by-name "stake-registry"))) ERR-WRONG-REGISTRY)

    (asserts! (is-eq 'SP3K8BC0PPEVCV7NZ6QSRWPQ2JE9E5B6N3PA0KBR9.token-amm-swap-pool (contract-of token)) ERR-WRONG-TOKEN)
    (asserts! (>= stake-amount amount) ERR-INSUFFICIENT-STAKE)

    ;; Save currrent cumm reward per stake
    (unwrap-panic (increase-cumm-reward-per-stake registry-trait))

    (let (
      ;; Calculate new stake amount
      (new-stake-amount (- stake-amount amount))
    )
      ;; Claim all pending rewards for staker so we can set the new cumm-reward for this user
      (try! (claim-pending-rewards registry-trait))

      ;; Update total stake
      (var-set total-staked (- (var-get total-staked) amount))

      ;; Update cumm reward per stake now that total is updated
      (unwrap-panic (increase-cumm-reward-per-stake registry-trait))

      ;; Transfer LP token back from this contract to the user
      (try! (as-contract (contract-call? 'SP3K8BC0PPEVCV7NZ6QSRWPQ2JE9E5B6N3PA0KBR9.token-amm-swap-pool transfer TOKEN-ID amount tx-sender staker)))

      ;; Update sender stake info
      (map-set stakes { staker: staker } { uamount: new-stake-amount, cumm-reward-per-stake: (var-get cumm-reward-per-stake) })

      (ok amount)
    )
  )
)

;; @desc unstake tokens without claiming rewards
;; @param registry-trait; current stake registry
;; @post uint; returns zero
(define-public (emergency-withdraw (registry-trait <stake-registry-trait>))
  (begin
    ;; Check given registry
    (asserts! (is-eq (contract-of registry-trait) (unwrap-panic (contract-call? .arkadiko-dao get-qualified-name-by-name "stake-registry"))) ERR-WRONG-REGISTRY)

    ;; Save currrent cumm reward per stake
    (unwrap-panic (increase-cumm-reward-per-stake registry-trait))

    (let (
      (stake-amount (get-stake-amount-of tx-sender))
      (new-stake-amount u0)
      (staker tx-sender)
    )
      ;; Update total stake
      (var-set total-staked (- (var-get total-staked) stake-amount))

      ;; Update cumm reward per stake now that total is updated
      (unwrap-panic (increase-cumm-reward-per-stake registry-trait))

      ;; Transfer LP token back from this contract to the user
      (try! (as-contract (contract-call? 'SP3K8BC0PPEVCV7NZ6QSRWPQ2JE9E5B6N3PA0KBR9.token-amm-swap-pool transfer TOKEN-ID stake-amount tx-sender staker)))

      ;; Update sender stake info
      (map-set stakes { staker: tx-sender } { uamount: new-stake-amount, cumm-reward-per-stake: (var-get cumm-reward-per-stake) })

      (ok new-stake-amount)
    )
  )
)

;; @desc get amount of pending rewards for staker
;; @param registry-trait; current stake registry
;; @param staker; user to get pending rewards for
;; @post uint; returns pending rewards
(define-public (get-pending-rewards (registry-trait <stake-registry-trait>) (staker principal))
  (let (
    (stake-amount (get-stake-amount-of staker))
    (amount-owed-per-token (- (unwrap-panic (calculate-cumm-reward-per-stake registry-trait)) (get-stake-cumm-reward-per-stake-of staker)))
    (rewards-decimals (* stake-amount amount-owed-per-token))
    (rewards (/ rewards-decimals u1000000))
  )
    (ok rewards)
  )
)

;; @desc claim pending rewards for staker, used by stake-registry
;; @param registry-trait; current stake registry
;; @post uint; returns claimed rewards
(define-public (claim-pending-rewards (registry-trait <stake-registry-trait>))
  (begin
    ;; Check given registry
    (asserts! (is-eq (contract-of registry-trait) (unwrap-panic (contract-call? .arkadiko-dao get-qualified-name-by-name "stake-registry"))) ERR-WRONG-REGISTRY)

    (unwrap-panic (increase-cumm-reward-per-stake registry-trait))

    (let (
      (staker tx-sender)

      (pending-rewards (unwrap! (get-pending-rewards registry-trait staker) ERR-REWARDS-CALC))
      (stake-of (get-stake-of staker))
    )
      ;; Only mint if enough pending rewards and amount is positive
      (if (>= pending-rewards u1)
        (begin
          ;; Mint DIKO rewards for staker
          (try! (contract-call? .arkadiko-dao mint-token .arkadiko-token pending-rewards staker))

          (map-set stakes { staker: staker } (merge stake-of { cumm-reward-per-stake: (var-get cumm-reward-per-stake) }))

          (ok pending-rewards)
        )
        (ok u0)
      )
    )
  )
)

;; @desc claim pending DIKO rewards for pool and immediately stake in DIKO pool
;; @param registry-trait; current stake registry, to be used by pool
;; @param diko-pool-trait; DIKO pool to stake rewards
;; @param diko-token-trait; DIKO token contract
;; @post uint; returns amount of claimed/staked rewards
(define-public (stake-pending-rewards 
    (registry-trait <stake-registry-trait>) 
    (diko-pool-trait <stake-pool-trait>)
    (diko-token-trait <ft-trait>)
  )
  (let (
    (claimed-rewards (unwrap-panic (claim-pending-rewards registry-trait)))
  )
    ;; Check given registry
    (asserts! (is-eq (contract-of registry-trait) (unwrap-panic (contract-call? .arkadiko-dao get-qualified-name-by-name "stake-registry"))) ERR-WRONG-REGISTRY)

    ;; Stake
    (contract-call? .arkadiko-stake-registry-v1-1 stake registry-trait diko-pool-trait diko-token-trait claimed-rewards)
  )
)


;; @desc increase cummulative rewards per stake and save
;; @param registry-trait; current stake registry
;; @post uint; returns saved cummulative rewards per stake
(define-public (increase-cumm-reward-per-stake (registry-trait <stake-registry-trait>))
  (let (
    ;; Calculate new cumm reward per stake
    (new-cumm-reward-per-stake (unwrap-panic (calculate-cumm-reward-per-stake registry-trait)))
    (last-block-height (get-last-block-height registry-trait))
  )
    (asserts! (is-eq (contract-of registry-trait) (unwrap-panic (contract-call? .arkadiko-dao get-qualified-name-by-name "stake-registry"))) ERR-WRONG-REGISTRY)
    (asserts! (> block-height (var-get last-reward-increase-block)) (ok u0))

    (var-set cumm-reward-per-stake new-cumm-reward-per-stake)
    (var-set last-reward-increase-block last-block-height)
    (ok new-cumm-reward-per-stake)
  )
)

;; @desc calculate current cumm reward per stake
;; @param registry-trait; current stake registry
;; @post uint; returns new cummulative rewards per stake
(define-public (calculate-cumm-reward-per-stake (registry-trait <stake-registry-trait>))
  (let (
    (rewards-per-block (unwrap-panic (contract-call? registry-trait get-rewards-per-block-for-pool .arkadiko-stake-pool-wstx-usda-v1-1)))
    (current-total-staked (var-get total-staked))
    (last-block-height (get-last-block-height registry-trait))
    (block-diff (if (> last-block-height (var-get last-reward-increase-block))
      (- last-block-height (var-get last-reward-increase-block))
      u0
    ))
    (current-cumm-reward-per-stake (var-get cumm-reward-per-stake)) 
  )
    (if (> current-total-staked u0)
      (let (
        (total-rewards-to-distribute (* rewards-per-block block-diff))
        (reward-added-per-token (/ (* total-rewards-to-distribute u1000000) current-total-staked))
        (new-cumm-reward-per-stake (+ current-cumm-reward-per-stake reward-added-per-token))
      )
        (ok new-cumm-reward-per-stake)
      )
      (ok current-cumm-reward-per-stake)
    )
  )
)

;; Helper for current-cumm-reward-per-stake
;; Return current block height, or block height when pool was deactivated
(define-private (get-last-block-height (registry-trait <stake-registry-trait>))
  (let (
    (deactivated-block (unwrap-panic (contract-call? registry-trait get-pool-deactivated-block .arkadiko-stake-pool-wstx-usda-v1-1)))
    (pool-active (is-eq deactivated-block u0))
  )
    (if (is-eq pool-active true)
      block-height
      deactivated-block
    )
  )
)

;; Initialize the contract
(begin
  (var-set last-reward-increase-block block-height)
)
