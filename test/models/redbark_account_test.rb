# frozen_string_literal: true

require "test_helper"

class RedbarkAccountTest < ActiveSupport::TestCase
  setup do
    @redbark_account = redbark_accounts(:savings_account)
  end

  test "sync_start_date allows nil" do
    @redbark_account.sync_start_date = nil
    assert @redbark_account.valid?
  end

  test "sync_start_date allows any date within the max lookback window" do
    @redbark_account.sync_start_date = 6.months.ago.to_date
    assert @redbark_account.valid?

    @redbark_account.sync_start_date = Date.current
    assert @redbark_account.valid?

    @redbark_account.sync_start_date = RedbarkAccount::MAX_SYNC_START_DATE_LOOKBACK_DAYS.days.ago.to_date
    assert @redbark_account.valid?
  end

  test "sync_start_date rejects a date older than the max lookback window" do
    @redbark_account.sync_start_date = (RedbarkAccount::MAX_SYNC_START_DATE_LOOKBACK_DAYS + 1).days.ago.to_date
    assert_not @redbark_account.valid?
    assert_includes @redbark_account.errors[:sync_start_date], "is not included in the list"
  end

  test "sync_start_date rejects a future date" do
    @redbark_account.sync_start_date = 1.day.from_now.to_date
    assert_not @redbark_account.valid?
    assert_includes @redbark_account.errors[:sync_start_date], "is not included in the list"
  end

  test "an unrelated update does not re-validate an unchanged, now-expired sync_start_date" do
    # Bypasses validation on write, simulating a date that was valid when set
    # but has since rolled outside the window - exactly what update_column
    # (not update!) would leave behind if it had ever been written that way.
    @redbark_account.update_column(:sync_start_date, (RedbarkAccount::MAX_SYNC_START_DATE_LOOKBACK_DAYS + 50).days.ago.to_date)

    assert_nothing_raised { @redbark_account.update!(current_balance: 999) }
  end

  test "changing sync_start_date to an out-of-range value is still rejected" do
    @redbark_account.update_column(:sync_start_date, 6.months.ago.to_date)

    @redbark_account.sync_start_date = (RedbarkAccount::MAX_SYNC_START_DATE_LOOKBACK_DAYS + 1).days.ago.to_date
    assert_not @redbark_account.valid?
    assert_includes @redbark_account.errors[:sync_start_date], "is not included in the list"
  end

  test "request_history_refill! raises when the account isn't linked" do
    assert_raises(ArgumentError) { @redbark_account.request_history_refill!(2.years.ago.to_date) }
  end

  test "request_history_refill! sets sync_start_date and clears the stored snapshot for a linked account" do
    link_redbark_account!
    @redbark_account.update!(raw_transactions_payload: [ { "id" => "tx_1" } ])
    new_date = 5.years.ago.to_date

    @redbark_account.request_history_refill!(new_date)

    assert_equal new_date, @redbark_account.reload.sync_start_date
    assert_nil @redbark_account.raw_transactions_payload
  end

  test "request_history_refill! raises on an out-of-range date without changing the account" do
    link_redbark_account!
    @redbark_account.update!(sync_start_date: 6.months.ago.to_date, raw_transactions_payload: [ { "id" => "tx_1" } ])
    out_of_range_date = (RedbarkAccount::MAX_SYNC_START_DATE_LOOKBACK_DAYS + 1).days.ago.to_date

    assert_raises(ActiveRecord::RecordInvalid) { @redbark_account.request_history_refill!(out_of_range_date) }

    @redbark_account.reload
    assert_equal 6.months.ago.to_date, @redbark_account.sync_start_date
    assert_equal [ { "id" => "tx_1" } ], @redbark_account.raw_transactions_payload
  end

  private
    def link_redbark_account!
      family = @redbark_account.redbark_item.family
      account = family.accounts.create!(name: "Linked Test Account", balance: 0, currency: "AUD", accountable: Depository.new)
      @redbark_account.ensure_account_provider!(account)
    end
end
