module Plugins::Ecommerce::EcommerceEmailHelper
  include CamaleonCms::EmailHelper

  def mark_order_like_received(order)
    order.make_paid!

    # send email to buyer
    commerce_send_order_received_email(order)

    # Send email to products owner
    commerce_send_order_received_admin_notice(order)

    flash[:notice] = t('plugins.ecommerce.messages.payment_completed', default: "Payment completed successfully")
    args = {order: order}; hooks_run("commerce_after_payment_completed", args)
  end

  def commerce_send_order_received_email(order)
    data = _commerce_prepare_send_order_email_data(order)
    cama_send_email(order.customer.email, t('plugin.ecommerce.email.order_received.subject'), {template_name: 'order_received', extra_data: data[:extra_data], attachs: data[:files]})
  end

  def commerce_send_order_received_admin_notice(order)
    data = _commerce_prepare_send_order_email_data(order)
    data[:owners].each do |user|
      data[:extra_data][:admin] = user
      cama_send_email(user.email, t('plugin.ecommerce.email.order_received_admin.subject'), {template_name: 'order_received_admin', extra_data: data[:extra_data], attachs: data[:files]})
    end
  end

  def send_recovery_cart_email(order)
    extra_data = {
      :fullname => order.customer.fullname,
      :order => order
    }
    send_email(order.customer.email, t('plugin.ecommerce.email.recovery_cart.subject'), '', nil, [], 'recovery_cart', nil, extra_data)
    Rails.logger.info "Send recovery to #{order.customer.email} with order #{order.slug}"
  end

  # return translated message
  def commerce_coupon_error_message(error_code, coupon = nil)
    case error_code
      when 'coupon_not_found'
        t('plugins.ecommerce.messages.coupon_not_found', default: "Coupon not found")
      when 'coupon_expired'
        t('plugins.ecommerce.messages.coupon_expired', default: 'Coupon Expired')
      when 'inactive_coupon'
        t('plugins.ecommerce.messages.inactive_coupon', default: 'Coupon disabled')
      when 'times_exceeded'
        t('plugins.ecommerce.messages.times_exceeded', default: 'Number of times exceeded')
      when 'required_minimum_price'
        t('plugins.ecommerce.messages.required_minimum_price', min_amount: coupon.min_cart_total, default: 'Your amount should be great than %{min_amount}')
      else
        'Unknown error'
    end
  end

  # verify all products and qty, coupons availability
  # return an array of errors
  def ecommerce_verify_cart_errors(order)
    errors = []

    # products verification
    order.product_items.each do |item|
      product = item.product.decorate
      unless product.decrement_qty(item.qty)
        errors << t('plugins.ecommerce.messages.not_enough_product_qty', product: product.the_title, qty: product.the_qty_real, default: 'There is not enough products "%{product}" (%{qty})')
      end
    end

    # coupon verification
    res = order.discount_for(order.coupon)
    errors << commerce_coupon_error_message(res[:error], res[:coupon]) if res[:error].present?

    args = {order: order, errors: errors}; hooks_run("commerce_on_error_verifications", args)
    errors
  end

  private
  def _commerce_prepare_send_order_email_data(order)
    data = {}
    data[:extra_data] = {
      :fullname => order.customer.fullname,
      :order_slug => order.slug,
      :order_url => plugins_ecommerce_order_show_url(order: order.slug),
      :billing_information => order.get_meta('billing_address'),
      :shipping_address => order.get_meta('shipping_address'),
      :subtotal => order.get_meta("payment")[:total],
      :total_cost => order.get_meta("payment")[:amount],
      :order => order
    }
    files = []
    owners = []
    order.products.each do |product|
      files += product.get_fields('ecommerce_files').map{|f| CamaleonCmsLocalUploader::private_file_path(f, current_site) }
      owners << product.owner if product.owner.present?
    end
    data[:owners] = owners.uniq
    data[:files] = files.uniq
    data
  end

end
