module Spree::Chimpy
  module Interface
    class Orders
      delegate :log, to: Spree::Chimpy

      def initialize
        @api = Spree::Chimpy.api
      end

      def add(order)
        if source = order.source
          info = Spree::Chimpy.list.info(source.email_id)
          # use the one from mail chimp or fall back to the order's email 
          # happens when this is a new user
          expected_email = (info[:email] || order.email).to_s
        else
          expected_email = order.email
        end        
        
        log "Adding order #{order.number} for #{expected_email}"

        # create the user if it does not exist yet 
        # Spree::Chimpy.list.subscribe(expected_email)

        @api.ecomm_order_add(order: hash(order, expected_email))
      end

      def remove(order)
        log "Attempting to remove order #{order.number}"

        @api.ecomm_order_del(store_id: Spree::Chimpy::Config.store_id, order_id: order.number, throws_exceptions: false)
      end

      def sync(order)
        remove(order)
        add(order)
      end

    private
      def hash(order, expected_email)
        source = order.source
        root_taxon = Spree::Taxon.where(parent_id: nil).take

        items = order.line_items.map do |line|
          # MC can only associate the order with a single category: associate the order with the category right below the root level taxon
          variant = line.variant
          taxon = variant.product.taxons.map(&:self_and_ancestors).flatten.uniq.detect { |t| t.parent == root_taxon }

          {product_id:    variant.id,
           sku:           variant.sku,
           product_name:  variant.name,
           category_id:   taxon ? taxon.id : 999999,
           category_name: taxon ? taxon.name : Spree.t(:uncategorized, scope: :chimpy, default: 'Uncategorized'),
           cost:          variant.price.to_f,
           qty:           line.quantity}
        end

        data = {
          id:          order.number,
          email:       order.email,
          total:       order.total.to_f,
          order_date:  order.completed_at ? order.completed_at.to_formatted_s(:db) : nil,
          shipping:    order.ship_total.to_f,
          tax:         order.try(:included_tax_total).to_f, # or additional_tax_total
          store_name:  Spree::Chimpy::Config.store_id.titleize,
          store_id:    Spree::Chimpy::Config.store_id,
          items:       items
        }

        if source && expected_email.upcase == order.email.upcase
          data[:email_id]    = source.email_id
          data[:campaign_id] = source.campaign_id
        end
        data
      end

    end
  end
end
