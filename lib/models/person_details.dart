/// A role a person holds at an HTW institution ("Funktionen" on LSF).
class PersonFunction {
  final String institution;
  final String role;

  const PersonFunction({required this.institution, required this.role});
}

/// A course a person teaches, as listed on their LSF page.
class PersonCourse {
  final String title;
  final String semester;

  /// LSF's `veranstaltung.veranstid`, which is also the lecture's publish id.
  final String? lectureId;

  const PersonCourse({
    required this.title,
    required this.semester,
    this.lectureId,
  });
}

/// The public profile of a lecturer from LSF's person page ("Einzelansicht").
///
/// Only work-related data LSF publishes for staff is read: name, title,
/// office address and contact, roles and courses.
class PersonDetails {
  final String personId;
  final String? title;
  final String? firstName;
  final String? lastName;
  final String? nameSuffix;

  /// LSF's "Personalstatus", e.g. "Lehrperson".
  final String? status;
  final String? remark;
  final String? consultationHours;
  final String? email;
  final String? phone;
  final String? street;
  final String? postalCode;
  final String? city;
  final String? room;
  final String? building;
  final Uri? homepage;
  final List<PersonFunction> functions;
  final List<PersonCourse> courses;

  const PersonDetails({
    required this.personId,
    this.title,
    this.firstName,
    this.lastName,
    this.nameSuffix,
    this.status,
    this.remark,
    this.consultationHours,
    this.email,
    this.phone,
    this.street,
    this.postalCode,
    this.city,
    this.room,
    this.building,
    this.homepage,
    this.functions = const [],
    this.courses = const [],
  });

  /// "Prof. Dr. Erika Mustermann", or null if LSF gave no name.
  String? get displayName {
    final parts = [title, firstName, nameSuffix, lastName]
        .whereType<String>()
        .where((part) => part.isNotEmpty);
    final name = parts.join(' ');
    return name.isEmpty ? null : name;
  }

  /// "Street, 12345 City", or null if LSF gave no address.
  String? get address {
    final cityLine = [postalCode, city]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(' ');
    final parts = [street, cityLine]
        .whereType<String>()
        .where((part) => part.isNotEmpty);
    final value = parts.join(', ');
    return value.isEmpty ? null : value;
  }

  /// "Room, Building", or null if LSF names neither.
  String? get office {
    final parts = [room, building]
        .whereType<String>()
        .where((part) => part.isNotEmpty);
    final value = parts.join(', ');
    return value.isEmpty ? null : value;
  }
}

