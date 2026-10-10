# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
#
# lvs_label_order.rb -- the label-ordered inductor terminal step (issue #80).
#
# A REVIEWED, REMOVABLE accommodation in this repo's LVS flow, not part of
# IHP's runset.  layout/lvs.sh includes this file ahead of the UNMODIFIED
# runset (sg13g2.lvs, hash-pinned in lvs.sh) through a generated wrapper deck.
# It changes exactly one thing: just before the runset's own `compare`, every
# extracted 2-terminal inductor's winding terminals are put in the order of the
# LA/LB labels the runset itself used to find those ports, instead of the
# x-position order the runset gave them.
#
# Why.  ind_derivations.lvs finds the two ports of an `inductor` by their LA /
# LB texts (layer 27/25, `ind_text`), but joins them into one region
# (`ind2_ports`), and custom_extractor.lvs (`define_and_sort_terminals` ->
# `sort_polygons`) then assigns inductor_1 / inductor_2 by the lexicographic
# order of each port polygon's first vertex, i.e. by x.  DeviceCustomInd
# clears terminal equivalence, so that order is compared.  A mirrored spiral
# therefore extracts with its windings reversed, whatever it is wired to.
# The PDK's own convention is LA = terminal 1, LB = terminal 2: its LVS unit
# testcase (testing/testcases/unit/ind_devices/netlist/inductor.cdl) names
# every pattern's nodes `la_N lb_N` in that order, and every pattern in the
# matching layout has LA to the left of LB -- which is why the x-sort agrees
# with the labels there and disagrees for a mirrored spiral.
#
# What it does, per extracted device whose class name starts with `ind`:
#   * class `inductor` only (a 3-terminal `inductor3` is refused, not guessed)
#   * device in the top circuit only (the flat run; terminal shapes are then in
#     top-cell coordinates)
#   * the terminal shapes of inductor_1 and inductor_2 come from the runset's
#     own LayoutToNetlist database (`shapes_of_terminal`); the LA / LB texts
#     come from the stream (27/25, case-insensitive, as the runset's glob)
#   * RESOLVED iff exactly one of the two terminals carries an LA text, exactly
#     one carries an LB text, and they are different terminals.  Then, if the
#     LA terminal is inductor_2, the two winding nets are swapped on that
#     device (mode `apply`).  Nothing else is touched: no net, no other device
#     class, no parameter, no substrate terminal, and the schematic side not
#     at all.
#   * anything else is UNRESOLVED: the device is left exactly as extracted and
#     the report says so; lvs.sh treats any unresolved device as a failure of
#     the run of record (fail closed).
# It keys on the labels at each device's own terminals, never on instance or
# cell names: L1 and L2 go through the same code.
#
# Inputs (-rd switches, passed by lvs.sh's klayout shim):
#   label_order_report  path of the JSON report this step writes (required)
#   label_order_mode    `apply` (default) or `report` (compute, change nothing;
#                       the fidelity control that shows the wrapper alone does
#                       not move the runset's verdict)
#
# Removal.  Drop this step (and the wrapper/shim in lvs.sh) once the pinned
# IHP-Open-PDK runset orders inductor terminals by label or declares the two
# windings equivalent (layout/PROVENANCE.md section 14.6), then re-check the
# plain runset result.

require 'json'

lo_report = $label_order_report.to_s
lo_mode = ($label_order_mode || 'apply').to_s
raise 'lvs_label_order.rb: -rd label_order_report=<path> is required' if lo_report.empty?
raise "lvs_label_order.rb: label_order_mode must be apply or report, not #{lo_mode}" \
  unless %w[apply report].include?(lo_mode)

lo_engine = self
lo_step = lambda do
  ly = lo_engine.source.layout
  top = lo_engine.source.cell_obj
  l2n = lo_engine.l2n_data
  dbu = ly.dbu
  if (l2n.internal_layout.dbu - dbu).abs > 1e-12
    raise "lvs_label_order.rb: database unit mismatch (#{l2n.internal_layout.dbu} vs #{dbu})"
  end
  um = ->(v) { (v * dbu).round(4) }

  # LA / LB texts, in top-cell coordinates (IHP layers_definitions.lvs:
  # ind_text = labels(27, 25); ind_derivations.lvs matches "LA"/"LB"
  # case-insensitively).
  labels = []
  li = ly.find_layer(27, 25)
  if li
    it = top.begin_shapes_rec(li)
    until it.at_end?
      s = it.shape
      if s.is_text?
        t = s.text.transformed(it.trans)
        name = t.string.upcase
        labels << [name, t.position] if %w[LA LB].include?(name)
      end
      it.next
    end
  end

  devices = []
  lo_engine.netlist.each_circuit do |c|
    c.each_device do |d|
      dc = d.device_class
      next unless dc.name.downcase.start_with?('ind')

      e = { 'device' => d.expanded_name, 'class' => dc.name, 'circuit' => c.name }
      devices << e
      if dc.name.downcase != 'inductor'
        e['resolved'] = false
        e['why'] = "class #{dc.name} is not handled (only the 2-terminal inductor)"
        next
      end
      if c.name != top.name
        e['resolved'] = false
        e['why'] = "device is not in the top circuit #{top.name}"
        next
      end
      tdefs = dc.terminal_definitions.to_h { |td| [td.name.downcase, td] }
      t1 = tdefs['inductor_1']
      t2 = tdefs['inductor_2']
      unless t1 && t2
        e['resolved'] = false
        e['why'] = 'class has no inductor_1/inductor_2 terminals'
        next
      end
      per = {}
      [t1, t2].each do |td|
        net = d.net_for_terminal(td.id)
        region = RBA::Region.new
        if net
          net.each_terminal do |ref|
            next unless ref.device.id == d.id && ref.terminal_id == td.id

            l2n.shapes_of_terminal(ref).each_value { |r| region += r }
          end
        end
        polys = []
        region.each { |poly| polys << poly }
        # Polygon#inside? counts a point on the boundary as inside: the PCell
        # puts each text on its port's outer edge.
        on = labels.select { |_, p| polys.any? { |poly| poly.inside?(p) } }.map(&:first)
        bb = region.bbox
        per[td.name] = { 'net' => net ? net.expanded_name : nil,
                         'labels' => on.sort,
                         'port_centre_um' => region.is_empty? ? nil : [um.call(bb.center.x), um.call(bb.center.y)] }
      end
      e['terminals'] = per
      la = [t1, t2].select { |td| per[td.name]['labels'].include?('LA') }
      lb = [t1, t2].select { |td| per[td.name]['labels'].include?('LB') }
      e['extracted_order'] = [per[t1.name]['net'], per[t2.name]['net']]
      unless la.size == 1 && lb.size == 1 && la[0].id != lb[0].id
        e['resolved'] = false
        e['why'] = "terminal labels #{per.transform_values { |v| v['labels'] }} are not " \
                   'exactly one LA and one LB on different terminals'
        next
      end
      e['resolved'] = true
      e['label_order'] = [per[la[0].name]['net'], per[lb[0].name]['net']]
      e['reordered'] = la[0].id == t2.id
      next unless e['reordered'] && lo_mode == 'apply'

      n1 = d.net_for_terminal(t1.id)
      n2 = d.net_for_terminal(t2.id)
      d.connect_terminal(t1.id, n2)
      d.connect_terminal(t2.id, n1)
      e['order_after_step'] = [d.net_for_terminal(t1.id).expanded_name,
                               d.net_for_terminal(t2.id).expanded_name]
    end
  end

  report = {
    'step' => 'label-ordered inductor terminals (layout/scripts/lvs_label_order.rb, issue #80)',
    'mode' => lo_mode,
    'label_layer' => '27/25',
    'labels_in_stream' => { 'LA' => labels.count { |n, _| n == 'LA' },
                            'LB' => labels.count { |n, _| n == 'LB' } },
    'inductor_devices' => devices.size,
    'unresolved' => devices.count { |e| !e['resolved'] },
    'reordered' => devices.count { |e| e['reordered'] && lo_mode == 'apply' },
    'devices' => devices
  }
  File.write(lo_report, "#{JSON.pretty_generate(report)}\n")
end

lo_compare = method(:compare)
define_singleton_method(:compare) do |*args|
  lo_step.call
  lo_compare.call(*args)
end
