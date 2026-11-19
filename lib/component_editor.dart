import 'package:flutter/material.dart';
import 'project_view.dart';
import 'design_system.dart';

String? validateComponentValue(String type, double v) {
  if (!v.isFinite) return 'Enter a finite value.';
  return switch (type) {
    'resistor' || 'potentiometer' =>
      v < 1e-6 || v > 1e12 ? 'Use 1 micro-ohm to 1 tera-ohm.' : null,
    'capacitor' => v < 1e-12 || v > 1 ? 'Use 1 pF to 1 F.' : null,
    'inductor' => v < 1e-9 || v > 1e6 ? 'Use 1 nH to 1 MH.' : null,
    'voltage' || 'current' =>
      v.abs() > 1e6 ? 'Source magnitude must be at most 1 million.' : null,
    'diode' => v < .15 || v > 1.2 ? 'Use 0.15 to 1.2 V at 1 mA.' : null,
    'led' => v < .8 || v > 3.6 ? 'Use 0.8 to 3.6 V at 1 mA.' : null,
    'zener' => v < .5 || v > 200 ? 'Use 0.5 to 200 V.' : null,
    'npn' ||
    'pnp' => v < 1 || v > 1000 ? 'Use a current gain from 1 to 1000.' : null,
    'switch' => v != 0 && v != 1 ? 'Choose open or closed.' : null,
    _ => null,
  };
}

class ComponentEditor extends StatefulWidget {
  const ComponentEditor({
    super.key,
    required this.component,
    required this.onApply,
  });
  final Map<String, dynamic> component;
  final void Function(Map<String, dynamic>) onApply;
  @override
  State<ComponentEditor> createState() => _ComponentEditorState();
}

class _ComponentEditorState extends State<ComponentEditor> {
  final form = GlobalKey<FormState>();
  late final label = TextEditingController(
    text: widget.component['label'] as String,
  );
  late final value = TextEditingController(
    text: engineering(widget.component['value'] as num).trim(),
  );
  late double wiper = ((widget.component['setting'] as num?) ?? .5).toDouble();
  late bool closed = (widget.component['value'] as num) > .5;
  String get type => widget.component['type'] as String;
  @override
  void dispose() {
    label.dispose();
    value.dispose();
    super.dispose();
  }

  String? check(String? raw) {
    try {
      return validateComponentValue(type, parseEngineering(raw ?? ''));
    } on FormatException catch (e) {
      return e.message;
    }
  }

  void apply() {
    if (!form.currentState!.validate()) return;
    final data = Map<String, dynamic>.from(widget.component);
    data['label'] = label.text.trim();
    data['value'] = type == 'ground'
        ? 0.0
        : type == 'switch'
        ? (closed ? 1.0 : 0.0)
        : parseEngineering(value.text);
    if (type == 'potentiometer') data['setting'] = wiper;
    widget.onApply(data);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (type) {
      'npn' || 'pnp' => 'Current gain β',
      'diode' || 'led' => 'Forward voltage at 1 mA',
      'zener' => 'Reverse breakdown voltage',
      'potentiometer' => 'Total resistance',
      'resistor' => 'Resistance · Ω',
      'capacitor' => 'Capacitance · F',
      'inductor' => 'Inductance · H',
      'voltage' => 'Voltage · V',
      'current' => 'Current · A',
      _ => 'Value (${componentUnits[type] ?? ''})',
    };
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          22,
          8,
          22,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SymbolPreview(
                      type,
                      size: 42,
                      color: partColor(type),
                      value: (widget.component['value'] as num).toDouble(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          componentNames[type]!,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.component['id'] as String,
                          style: const TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                componentDescriptions[type]!,
                style: const TextStyle(color: muted, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('component-label'),
                controller: label,
                maxLength: 24,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Reference label'),
                validator: (s) =>
                    s == null || s.trim().isEmpty ? 'Enter a label.' : null,
              ),
              if (type == 'switch') ...[
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Open'),
                      icon: Icon(Icons.radio_button_unchecked),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Closed'),
                      icon: Icon(Icons.check_circle_outline),
                    ),
                  ],
                  selected: {closed},
                  onSelectionChanged: (s) => setState(() => closed = s.first),
                ),
              ] else if (type != 'ground') ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('component-value'),
                  controller: value,
                  style: technical(size: 18, color: softWhite),
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: title,
                    helperText: ['npn', 'pnp'].contains(type)
                        ? 'Collector/base current ratio in active operation.'
                        : 'SI prefixes work: 4.7k, 10u, 22m.',
                    helperMaxLines: 2,
                  ),
                  validator: check,
                  onFieldSubmitted: (_) => apply(),
                ),
              ],
              if (type == 'potentiometer') ...[
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Wiper position'),
                    Text(
                      '${(wiper * 100).round()}%',
                      style: const TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Slider(
                  key: const ValueKey('wiper-setting'),
                  value: wiper,
                  min: 0,
                  max: 1,
                  divisions: 100,
                  onChanged: (v) => setState(() => wiper = v),
                ),
                const Text(
                  '0% is terminal A; 100% is terminal B.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: canvasDark,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(switch (type) {
                  'npn' || 'pnp' =>
                    'Pins: C collector, E emitter, B base. Readings use VCE and collector current. The model includes forward and reverse junctions.',
                  'potentiometer' =>
                    'Pins: A and B are the track ends; W is the wiper. Connect W to the part you want to control.',
                  'diode' || 'led' =>
                    'Pins: A anode, K cathode. Add a series resistor to limit forward current.',
                  'zener' =>
                    'Pins: A anode, K cathode. Reverse regulation uses a 10 Ω breakdown slope.',
                  'inductor' =>
                    'DC: ideal short circuit. Transient: starts at zero current.',
                  'capacitor' =>
                    'DC: open circuit. Transient: starts at zero voltage.',
                  'switch' =>
                    'Closed resistance: 1 mΩ. Open resistance: 1 TΩ. Double-tap the switch on the canvas to toggle it.',
                  _ => 'Voltage is measured from terminal + to terminal −.',
                }, style: const TextStyle(color: muted, fontSize: 12, height: 1.5)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('apply-component'),
                onPressed: apply,
                icon: const Icon(Icons.check),
                label: const Padding(
                  padding: EdgeInsets.all(13),
                  child: Text('Apply changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
