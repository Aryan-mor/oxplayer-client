import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;

/// TDLib/tdweb JSON often omits or nulls fields the generated Dart API models as
/// non-nullable [bool]. [Map] lookup returns `null` for both — default those wire keys
/// to `false` before [td.convertToObject] (auth states, [profilePhoto], [user], …).
const _kTdlibJsonBoolKeysNullableOnWire = <String>{
  'added_to_attachment_menu',
  'allow_apple_id',
  'allow_google_id',
  'by_my_privacy_settings',
  'can_be_called',
  'can_be_deleted',
  'can_be_deleted_for_all_users',
  'can_be_deleted_only_for_self',
  'can_be_downloaded',
  'can_be_reported',
  'can_be_saved',
  'contains_unread_mention',
  'contains_unread_poll_votes',
  'default_disable_notification',
  'disable_mention_notifications',
  'disable_pinned_message_notifications',
  'has_animation',
  'has_passport_data',
  'has_posted_to_profile_stories',
  'has_private_calls',
  'has_private_forwards',
  'has_protected_content',
  'has_recovery_email_address',
  'has_restricted_voice_and_video_note_messages',
  'has_scheduled_messages',
  'has_sponsored_messages_enabled',
  'has_timestamped_media',
  'have_access',
  'is_channel_post',
  'is_close_friend',
  'is_contact',
  'is_downloading_active',
  'is_downloading_completed',
  'is_from_offline',
  'is_marked_as_unread',
  'is_mutual_contact',
  'is_outgoing',
  'is_paid_star_suggested_post',
  'is_paid_ton_suggested_post',
  'is_personal',
  'is_pinned',
  'is_premium',
  'is_support',
  'is_translatable',
  'is_uploading_active',
  'is_uploading_completed',
  'mute_stories',
  'need_phone_number_privacy_exception',
  'restricts_new_chats',
  'set_chat_background',
  'show_popup',
  'show_preview',
  'show_story_poster',
  'supports_video_calls',
  'uses_unofficial_app',
  'use_default_disable_mention_notifications',
  'use_default_disable_pinned_message_notifications',
  'use_default_mute_for',
  'use_default_mute_stories',
  'use_default_show_preview',
  'use_default_show_story_poster',
  'use_default_sound',
  'use_default_story_sound',
  'view_as_topics',
};

final _kTdwebEmptyLocalFileWire = <String, dynamic>{
  '@type': 'localFile',
  'path': '',
  'can_be_downloaded': false,
  'can_be_deleted': false,
  'is_downloading_active': false,
  'is_downloading_completed': false,
  'download_offset': 0,
  'downloaded_prefix_size': 0,
  'downloaded_size': 0,
};

final _kTdwebEmptyRemoteFileWire = <String, dynamic>{
  '@type': 'remoteFile',
  'id': '',
  'unique_id': '',
  'is_uploading_active': false,
  'is_uploading_completed': false,
  'uploaded_size': 0,
};

/// Minimal [file] for nested [PhotoSize.photo] when tdweb omits it.
final _kTdwebMinimalFileWire = <String, dynamic>{
  '@type': 'file',
  'id': 0,
  'size': 0,
  'expected_size': 0,
  'local': Map<String, dynamic>.from(_kTdwebEmptyLocalFileWire),
  'remote': Map<String, dynamic>.from(_kTdwebEmptyRemoteFileWire),
};

final _kTdwebMinimalVideoChatWire = <String, dynamic>{
  '@type': 'videoChat',
  'group_call_id': 0,
  'has_participants': false,
};

final _kTdwebMinimalChatPermissionsWire = <String, dynamic>{
  '@type': 'chatPermissions',
  'can_send_basic_messages': false,
  'can_send_audios': false,
  'can_send_documents': false,
  'can_send_photos': false,
  'can_send_videos': false,
  'can_send_video_notes': false,
  'can_send_voice_notes': false,
  'can_send_polls': false,
  'can_send_other_messages': false,
  'can_add_link_previews': false,
  'can_react_to_messages': false,
  'can_edit_tag': false,
  'can_change_info': false,
  'can_invite_users': false,
  'can_pin_messages': false,
  'can_create_topics': false,
};

final _kTdwebMinimalChatNotificationSettingsWire = <String, dynamic>{
  '@type': 'chatNotificationSettings',
  'use_default_mute_for': false,
  'mute_for': 0,
  'use_default_sound': false,
  'sound_id': '0',
  'use_default_show_preview': false,
  'show_preview': false,
  'use_default_mute_stories': false,
  'mute_stories': false,
  'use_default_story_sound': false,
  'story_sound_id': '0',
  'use_default_show_story_poster': false,
  'show_story_poster': false,
  'use_default_disable_pinned_message_notifications': false,
  'disable_pinned_message_notifications': false,
  'use_default_disable_mention_notifications': false,
  'disable_mention_notifications': false,
};

final _kTdwebDefaultAvailableReactionsAllWire = <String, dynamic>{
  '@type': 'chatAvailableReactionsAll',
  'max_reaction_count': 11,
};

void _coerceNullableDoubleSeconds(Map<String, dynamic> map, String key) {
  final v = map[key];
  if (v == null) {
    map[key] = 0.0;
  } else if (v is num) {
    map[key] = v.toDouble();
  }
}

/// [ScopeNotificationSettings]/[ChatNotificationSettings] use [int.parse] on `sound_id` /
/// `story_sound_id`. tdweb may send legacy `sound: "106.m4a"` — coerce non-numeric strings.
void _coerceSoundIdWireForIntParse(Map<String, dynamic> map, String key) {
  final v = map[key];
  if (v == null) {
    map[key] = '-1';
    return;
  }
  if (v is num) {
    map[key] = v.toInt().toString();
    return;
  }
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty || int.tryParse(t) == null) {
      map[key] = '-1';
    }
  }
}

Map<String, dynamic> _syntheticChatAdministratorRightsWire(
  Map<String, dynamic> legacyAdminStatus,
) {
  bool on(String k) => legacyAdminStatus[k] == true;
  return <String, dynamic>{
    '@type': 'chatAdministratorRights',
    'can_manage_chat': on('can_manage_chat'),
    'can_change_info': on('can_change_info'),
    'can_post_messages': on('can_post_messages'),
    'can_edit_messages': on('can_edit_messages'),
    'can_delete_messages': on('can_delete_messages'),
    'can_invite_users': on('can_invite_users'),
    'can_restrict_members': on('can_restrict_members'),
    'can_pin_messages': on('can_pin_messages'),
    'can_manage_topics': on('can_manage_topics'),
    'can_promote_members': on('can_promote_members'),
    'can_manage_video_chats': on('can_manage_video_chats'),
    'can_post_stories': on('can_post_stories'),
    'can_edit_stories': on('can_edit_stories'),
    'can_delete_stories': on('can_delete_stories'),
    'can_manage_direct_messages': on('can_manage_direct_messages'),
    'can_manage_tags': on('can_manage_tags'),
    'is_anonymous': on('is_anonymous'),
  };
}

/// [ChatPhoto.id] / [ProfilePhoto.id] use [int.parse] on a string. On web, integers are
/// JS numbers (53-bit); very large wire ids must be coerced before [int.parse].
/// On VM, full decimal strings are preserved.
String _wireInt64IdForIntParse(Object? idv) {
  const maxJsSafe = 9007199254740991; // 2^53 - 1
  final maxBi = BigInt.from(maxJsSafe);
  final mask53 = (BigInt.one << 53) - BigInt.one;

  if (idv == null) {
    return '0';
  }
  if (idv is String) {
    if (idv.isEmpty) {
      return '0';
    }
    if (kIsWeb) {
      final bi = BigInt.tryParse(idv);
      if (bi != null && bi.abs() > maxBi) {
        return (bi & mask53).toString();
      }
    }
    return idv;
  }
  if (idv is int) {
    if (kIsWeb) {
      final bi = BigInt.from(idv);
      if (bi.abs() > maxBi) {
        return (bi & mask53).toString();
      }
    }
    return idv.toString();
  }
  if (idv is num) {
    final d = idv.toDouble();
    if (!d.isFinite) {
      return '0';
    }
    final r = d.round();
    if ((r - d).abs() > 1e-6) {
      return '0';
    }
    if (kIsWeb && r.abs() > maxJsSafe) {
      return (BigInt.from(r) & mask53).toString();
    }
    return r.toString();
  }
  return '0';
}

Map<String, dynamic> _newEmptyGiftSettingsWire() {
  return <String, dynamic>{
    '@type': 'giftSettings',
    'show_gift_button': false,
    'accepted_gift_types': <String, dynamic>{
      '@type': 'acceptedGiftTypes',
      'unlimited_gifts': false,
      'limited_gifts': false,
      'upgraded_gifts': false,
      'gifts_from_channels': false,
      'premium_subscription': false,
    },
  };
}

const _kUserFullInfoOptionalObjectWireKeys = <String>{
  'bio',
  'birthdate',
  'block_list',
  'bot_info',
  'bot_verification',
  'business_info',
  'first_profile_audio',
  'main_profile_tab',
  'note',
  'pending_rating',
  'personal_photo',
  'photo',
  'public_photo',
  'rating',
};

void _applyTypedObjectWireFixups(Map<String, dynamic> map) {
  var t = map['@type']?.toString();
  if (t == null || t.isEmpty) {
    if (map['sizes'] is List && map.containsKey('added_date')) {
      map['@type'] = 'chatPhoto';
      t = 'chatPhoto';
    } else if (map.containsKey('photo') &&
        map.containsKey('width') &&
        map.containsKey('type') &&
        !map.containsKey('added_date')) {
      map['@type'] = 'photoSize';
      t = 'photoSize';
    }
  }
  switch (t) {
    case 'file':
      for (final k in ['id', 'size', 'expected_size']) {
        if (map[k] == null) {
          map[k] = 0;
        }
      }
      if (map['local'] is! Map) {
        map['local'] = Map<String, dynamic>.from(_kTdwebEmptyLocalFileWire);
      } else {
        final lm = map['local'] is Map<String, dynamic>
            ? map['local'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['local'] as Map);
        map['local'] = lm;
        lm['@type'] ??= 'localFile';
      }
      if (map['remote'] is! Map) {
        map['remote'] = Map<String, dynamic>.from(_kTdwebEmptyRemoteFileWire);
      } else {
        final rm = map['remote'] is Map<String, dynamic>
            ? map['remote'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['remote'] as Map);
        map['remote'] = rm;
        rm['@type'] ??= 'remoteFile';
      }
      break;
    case 'localFile':
      for (final k in [
        'can_be_downloaded',
        'can_be_deleted',
        'is_downloading_active',
        'is_downloading_completed',
      ]) {
        if (map[k] == null) {
          map[k] = false;
        }
      }
      for (final k in ['download_offset', 'downloaded_prefix_size', 'downloaded_size']) {
        if (map[k] == null) {
          map[k] = 0;
        }
      }
      if (map['path'] == null) {
        map['path'] = '';
      }
      break;
    case 'remoteFile':
      for (final k in ['is_uploading_active', 'is_uploading_completed']) {
        if (map[k] == null) {
          map[k] = false;
        }
      }
      if (map['uploaded_size'] == null) {
        map['uploaded_size'] = 0;
      }
      if (map['id'] == null) {
        map['id'] = '';
      }
      if (map['unique_id'] == null) {
        map['unique_id'] = '';
      }
      break;
    case 'videoChat':
      if (map['group_call_id'] == null) {
        map['group_call_id'] = 0;
      }
      if (map['has_participants'] == null) {
        map['has_participants'] = false;
      }
      break;
    case 'chatPermissions':
      for (final k in [
        'can_send_basic_messages',
        'can_send_audios',
        'can_send_documents',
        'can_send_photos',
        'can_send_videos',
        'can_send_video_notes',
        'can_send_voice_notes',
        'can_send_polls',
        'can_send_other_messages',
        'can_add_link_previews',
        'can_react_to_messages',
        'can_edit_tag',
        'can_change_info',
        'can_invite_users',
        'can_pin_messages',
        'can_create_topics',
      ]) {
        if (map[k] == null) {
          map[k] = false;
        }
      }
      break;
    case 'chatAvailableReactionsAll':
      if (map['max_reaction_count'] == null) {
        map['max_reaction_count'] = 11;
      }
      break;
    case 'chatAvailableReactionsSome':
      if (map['reactions'] == null) {
        map['reactions'] = <dynamic>[];
      }
      if (map['max_reaction_count'] == null) {
        map['max_reaction_count'] = 11;
      }
      break;
    case 'chatMemberStatusMember':
      if (map['member_until_date'] == null) {
        map['member_until_date'] = 0;
      }
      break;
    case 'chatMemberStatusCreator':
      for (final k in ['is_anonymous', 'is_member']) {
        if (map[k] == null) {
          map[k] = false;
        }
      }
      if (map['custom_title'] == null) {
        map['custom_title'] = '';
      }
      break;
    case 'chatMemberStatusAdministrator':
      if (map['rights'] == null || map['rights'] is! Map) {
        map['rights'] = _syntheticChatAdministratorRightsWire(map);
      } else {
        final rm = map['rights'] is Map<String, dynamic>
            ? map['rights'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['rights'] as Map);
        map['rights'] = rm;
        rm['@type'] ??= 'chatAdministratorRights';
      }
      if (map['can_be_edited'] == null) {
        map['can_be_edited'] = false;
      }
      if (map['custom_title'] == null) {
        map['custom_title'] = '';
      }
      break;
    case 'supergroupFullInfo':
      if (map['description'] == null) {
        map['description'] = '';
      }
      for (final k in [
        'member_count',
        'administrator_count',
        'restricted_count',
        'banned_count',
        'slow_mode_delay',
        'gift_count',
        'my_boost_count',
        'unrestrict_boost_count',
        'outgoing_paid_message_star_count',
      ]) {
        if (map[k] == null) {
          map[k] = 0;
        }
      }
      _coerceNullableDoubleSeconds(map, 'slow_mode_delay_expires_in');
      for (final k in [
        'can_enable_paid_messages',
        'can_enable_paid_reaction',
        'can_get_members',
        'has_hidden_members',
        'can_hide_members',
        'can_set_sticker_set',
        'can_set_location',
        'can_get_statistics',
        'can_get_revenue_statistics',
        'can_get_star_revenue_statistics',
        'can_send_gift',
        'can_toggle_aggressive_anti_spam',
        'is_all_history_available',
        'can_have_sponsored_messages',
        'has_aggressive_anti_spam_enabled',
        'has_paid_media_allowed',
        'has_pinned_stories',
      ]) {
        if (map[k] == null) {
          map[k] = false;
        }
      }
      if (map['bot_commands'] == null) {
        map['bot_commands'] = <dynamic>[];
      }
      break;
    case 'inlineKeyboardButton':
      if (map['text'] == null) {
        map['text'] = '';
      }
      final style = map['style'];
      if (style is! Map) {
        map['style'] = <String, dynamic>{'@type': 'buttonStyleDefault'};
      } else {
        final sm = style is Map<String, dynamic> ? style : Map<String, dynamic>.from(style);
        map['style'] = sm;
        sm['@type'] ??= 'buttonStyleDefault';
      }
      if (map['type'] == null || map['type'] is! Map) {
        final url = map['url'];
        if (url is String && url.isNotEmpty) {
          map['type'] = <String, dynamic>{
            '@type': 'inlineKeyboardButtonTypeUrl',
            'url': url,
          };
        } else if (map['web_app'] is Map) {
          final wa = map['web_app'] is Map<String, dynamic>
              ? map['web_app'] as Map<String, dynamic>
              : Map<String, dynamic>.from(map['web_app'] as Map);
          final wu = wa['url'];
          map['type'] = <String, dynamic>{
            '@type': 'inlineKeyboardButtonTypeWebApp',
            'url': wu is String ? wu : '',
          };
        } else if (map['login_url'] is Map) {
          final lu = map['login_url'] is Map<String, dynamic>
              ? map['login_url'] as Map<String, dynamic>
              : Map<String, dynamic>.from(map['login_url'] as Map);
          map['type'] = <String, dynamic>{
            '@type': 'inlineKeyboardButtonTypeLoginUrl',
            'url': lu['url'] is String ? lu['url'] as String : '',
            'id': lu['id'] ?? 0,
            'forward_text': lu['forward_text'] is String ? lu['forward_text'] as String : '',
          };
        } else if (map['callback_data'] is String &&
            (map['callback_data'] as String).isNotEmpty) {
          map['type'] = <String, dynamic>{
            '@type': 'inlineKeyboardButtonTypeCallback',
            'data': map['callback_data'],
          };
        } else if (map['switch_inline_query'] is String) {
          map['type'] = <String, dynamic>{
            '@type': 'inlineKeyboardButtonTypeSwitchInline',
            'query': map['switch_inline_query'],
            'target_chat': <String, dynamic>{
              '@type': 'targetChatChosen',
              'types': <String, dynamic>{
                '@type': 'targetChatTypes',
                'allow_user_chats': true,
                'allow_bot_chats': true,
                'allow_group_chats': true,
                'allow_channel_chats': true,
              },
            },
          };
        } else if (map['switch_inline_query_current_chat'] is String) {
          map['type'] = <String, dynamic>{
            '@type': 'inlineKeyboardButtonTypeSwitchInline',
            'query': map['switch_inline_query_current_chat'],
            'target_chat': <String, dynamic>{'@type': 'targetChatCurrent'},
          };
        } else if (map['callback_game'] != null) {
          map['type'] = <String, dynamic>{
            '@type': 'inlineKeyboardButtonTypeCallbackGame',
          };
        } else if (map['copy_text'] is String &&
            (map['copy_text'] as String).isNotEmpty) {
          map['type'] = <String, dynamic>{
            '@type': 'inlineKeyboardButtonTypeCopyText',
            'text': map['copy_text'],
          };
        } else if (map['pay'] == true) {
          map['type'] = <String, dynamic>{
            '@type': 'inlineKeyboardButtonTypeBuy',
          };
        } else if (map['user_id'] is int || map['user_id'] is num) {
          map['type'] = <String, dynamic>{
            '@type': 'inlineKeyboardButtonTypeUser',
            'user_id': (map['user_id'] as num).toInt(),
          };
        } else {
          map['type'] = <String, dynamic>{
            '@type': 'inlineKeyboardButtonTypeCallback',
            'data': '',
          };
        }
      } else {
        final tm = map['type'] is Map<String, dynamic>
            ? map['type'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['type'] as Map);
        map['type'] = tm;
      }
      break;
    case 'sticker':
      if (map['format'] == null || map['format'] is! Map) {
        map['format'] = <String, dynamic>{'@type': 'stickerFormatWebp'};
      } else {
        final fm = map['format'] is Map<String, dynamic>
            ? map['format'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['format'] as Map);
        map['format'] = fm;
        fm['@type'] ??= 'stickerFormatWebp';
      }
      if (map['full_type'] == null || map['full_type'] is! Map) {
        map['full_type'] = <String, dynamic>{'@type': 'stickerFullTypeRegular'};
      } else {
        final ft = map['full_type'] is Map<String, dynamic>
            ? map['full_type'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['full_type'] as Map);
        map['full_type'] = ft;
        ft['@type'] ??= 'stickerFullTypeRegular';
      }
      for (final k in ['width', 'height']) {
        if (map[k] == null) {
          map[k] = 0;
        }
      }
      if (map['emoji'] == null) {
        map['emoji'] = '';
      }
      break;
    case 'supergroup':
      for (final k in [
        'boost_level',
        'member_count',
        'paid_message_star_count',
      ]) {
        if (map[k] == null) {
          map[k] = 0;
        }
      }
      for (final k in [
        'has_automatic_translation',
        'has_linked_chat',
        'has_location',
        'sign_messages',
        'show_message_sender',
        'join_to_send_messages',
        'join_by_request',
        'is_slow_mode_enabled',
        'is_channel',
        'is_broadcast_group',
        'is_forum',
        'is_direct_messages_group',
        'is_administered_direct_messages_group',
        'has_direct_messages_group',
        'has_forum_tabs',
        'is_scam',
        'is_fake',
      ]) {
        if (map[k] == null) {
          map[k] = false;
        }
      }
      if (map['restriction_reason'] == null) {
        map['restriction_reason'] = '';
      }
      break;
    case 'minithumbnail':
      for (final k in ['width', 'height']) {
        if (map[k] == null) {
          map[k] = 0;
        }
      }
      if (map['data'] == null) {
        map['data'] = '';
      }
      break;
    case 'profilePhoto':
      for (final k in ['small', 'big']) {
        final v = map[k];
        if (v is Map) {
          final fm = Map<String, dynamic>.from(v);
          map[k] = fm;
          fm['@type'] ??= 'file';
        }
      }
      if (map['small'] is! Map) {
        map['small'] = Map<String, dynamic>.from(_kTdwebMinimalFileWire);
      }
      if (map['big'] is! Map) {
        if (map['small'] is Map) {
          map['big'] = Map<String, dynamic>.from(map['small'] as Map);
          (map['big'] as Map<String, dynamic>)['@type'] ??= 'file';
        } else {
          map['big'] = Map<String, dynamic>.from(_kTdwebMinimalFileWire);
        }
      }
      map['id'] = _wireInt64IdForIntParse(map['id']);
      break;
    case 'chatPhoto':
      map['id'] = _wireInt64IdForIntParse(map['id']);
      if (map['added_date'] == null) {
        map['added_date'] = 0;
      }
      if (map['sizes'] is! List) {
        map['sizes'] = <dynamic>[];
      }
      final sizes = map['sizes'];
      if (sizes is List) {
        final out = <dynamic>[];
        for (final s in sizes) {
          if (s is Map) {
            final sm = Map<String, dynamic>.from(s);
            sm['@type'] ??= 'photoSize';
            out.add(sm);
          }
        }
        map['sizes'] = out;
      }
      for (final k in ['animation', 'small_animation', 'sticker']) {
        final v = map[k];
        if (v is String && v.isEmpty) {
          map[k] = null;
        } else if (v != null && v is! Map) {
          map[k] = null;
        }
      }
      for (final k in ['animation', 'small_animation']) {
        final v = map[k];
        if (v is Map) {
          final m = Map<String, dynamic>.from(v);
          map[k] = m;
          m['@type'] ??= 'animatedChatPhoto';
        }
      }
      final st = map['sticker'];
      if (st is Map) {
        final m = Map<String, dynamic>.from(st);
        map['sticker'] = m;
        m['@type'] ??= 'chatPhotoSticker';
      }
      break;
    case 'animatedChatPhoto':
      if (map['length'] == null) {
        map['length'] = 0;
      }
      _coerceNullableDoubleSeconds(map, 'main_frame_timestamp');
      if (map['file'] is! Map) {
        map['file'] = Map<String, dynamic>.from(_kTdwebMinimalFileWire);
      } else {
        final fm = map['file'] is Map<String, dynamic>
            ? map['file'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['file'] as Map);
        map['file'] = fm;
        fm['@type'] ??= 'file';
      }
      break;
    case 'photoSize':
      if (map['type'] == null) {
        map['type'] = '';
      }
      if (map['width'] == null) {
        map['width'] = 0;
      }
      if (map['height'] == null) {
        map['height'] = 0;
      }
      if (map['photo'] is! Map) {
        map['photo'] = Map<String, dynamic>.from(_kTdwebMinimalFileWire);
      } else {
        final pm = map['photo'] is Map<String, dynamic>
            ? map['photo'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['photo'] as Map);
        map['photo'] = pm;
        pm['@type'] ??= 'file';
      }
      final ps = map['progressive_sizes'];
      if (ps is List) {
        map['progressive_sizes'] = ps.map((e) {
          if (e == null) {
            return 0;
          }
          if (e is int) {
            return e;
          }
          if (e is num) {
            return e.toInt();
          }
          return 0;
        }).toList();
      }
      break;
    case 'chat':
      if (map['id'] == null) {
        map['id'] = 0;
      }
      if (map['title'] == null) {
        map['title'] = '';
      }
      if (map['client_data'] == null) {
        map['client_data'] = '';
      }
      for (final k in [
        'accent_color_id',
        'profile_accent_color_id',
        'unread_count',
        'last_read_inbox_message_id',
        'last_read_outbox_message_id',
        'unread_mention_count',
        'unread_reaction_count',
        'unread_poll_vote_count',
        'message_auto_delete_time',
        'reply_markup_message_id',
      ]) {
        if (map[k] == null) {
          map[k] = 0;
        }
      }
      if (map['video_chat'] is! Map) {
        map['video_chat'] = Map<String, dynamic>.from(_kTdwebMinimalVideoChatWire);
      } else {
        final vc = map['video_chat'] is Map<String, dynamic>
            ? map['video_chat'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['video_chat'] as Map);
        map['video_chat'] = vc;
        vc['@type'] ??= 'videoChat';
      }
      if (map['permissions'] is! Map) {
        map['permissions'] = Map<String, dynamic>.from(_kTdwebMinimalChatPermissionsWire);
      } else {
        final perm = map['permissions'] is Map<String, dynamic>
            ? map['permissions'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['permissions'] as Map);
        map['permissions'] = perm;
        perm['@type'] ??= 'chatPermissions';
      }
      if (map['notification_settings'] is! Map) {
        map['notification_settings'] =
            Map<String, dynamic>.from(_kTdwebMinimalChatNotificationSettingsWire);
      } else {
        final ns = map['notification_settings'] is Map<String, dynamic>
            ? map['notification_settings'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['notification_settings'] as Map);
        map['notification_settings'] = ns;
        ns['@type'] ??= 'chatNotificationSettings';
      }
      if (map['available_reactions'] is! Map) {
        map['available_reactions'] =
            Map<String, dynamic>.from(_kTdwebDefaultAvailableReactionsAllWire);
      } else {
        final ar = map['available_reactions'] is Map<String, dynamic>
            ? map['available_reactions'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['available_reactions'] as Map);
        map['available_reactions'] = ar;
        ar['@type'] ??=
            ar.containsKey('reactions') ? 'chatAvailableReactionsSome' : 'chatAvailableReactionsAll';
      }
      final photo = map['photo'];
      if (photo is Map) {
        final pm = Map<String, dynamic>.from(photo);
        map['photo'] = pm;
        pm['@type'] ??= 'chatPhotoInfo';
      }
      break;
    case 'chatPhotoInfo':
      for (final k in ['small', 'big']) {
        final v = map[k];
        if (v is Map) {
          final fm = Map<String, dynamic>.from(v);
          map[k] = fm;
          fm['@type'] ??= 'file';
        }
      }
      if (map['small'] is! Map) {
        map['small'] = Map<String, dynamic>.from(_kTdwebMinimalFileWire);
      }
      if (map['big'] is! Map) {
        if (map['small'] is Map) {
          map['big'] = Map<String, dynamic>.from(map['small'] as Map);
          (map['big'] as Map<String, dynamic>)['@type'] ??= 'file';
        } else {
          map['big'] = Map<String, dynamic>.from(_kTdwebMinimalFileWire);
        }
      }
      break;
    case 'chatNotificationSettings':
      if (map['sound_id'] == null && map.containsKey('sound')) {
        final legacy = map['sound'];
        if (legacy == null ||
            legacy == 'default' ||
            (legacy is String && legacy.trim().isEmpty)) {
          map['sound_id'] = '0';
        } else if (legacy is num) {
          map['sound_id'] = legacy.toInt().toString();
        } else if (legacy is String) {
          final t = legacy.trim();
          map['sound_id'] =
              (t == 'default' || int.tryParse(t) == null) ? '0' : t;
        } else {
          map['sound_id'] = '0';
        }
      }
      map.remove('sound');
      _coerceSoundIdWireForIntParse(map, 'sound_id');
      _coerceSoundIdWireForIntParse(map, 'story_sound_id');
      if (map['mute_for'] == null) {
        map['mute_for'] = 0;
      }
      break;
    case 'scopeNotificationSettings':
      // tdweb may send legacy `sound` ("default") and omit `sound_id` / `story_sound_id` /
      // story fields — [ScopeNotificationSettings.fromJson] uses [int.parse] on string ids.
      if (map['mute_for'] == null) {
        map['mute_for'] = 0;
      }
      if (map['sound_id'] == null) {
        final legacy = map['sound'];
        if (legacy == null ||
            legacy == 'default' ||
            (legacy is String && legacy.trim().isEmpty)) {
          map['sound_id'] = '-1';
        } else if (legacy is num) {
          map['sound_id'] = legacy.toInt().toString();
        } else if (legacy is String) {
          final t = legacy.trim();
          map['sound_id'] =
              (t == 'default' || int.tryParse(t) == null) ? '-1' : t;
        } else {
          map['sound_id'] = '-1';
        }
      }
      map.remove('sound');
      _coerceSoundIdWireForIntParse(map, 'sound_id');
      _coerceSoundIdWireForIntParse(map, 'story_sound_id');
      for (final k in [
        'show_preview',
        'use_default_mute_stories',
        'mute_stories',
        'show_story_poster',
        'disable_pinned_message_notifications',
        'disable_mention_notifications',
      ]) {
        if (map[k] == null) {
          map[k] = false;
        }
      }
      break;
    case 'giftSettings':
      if (map['show_gift_button'] == null) {
        map['show_gift_button'] = false;
      }
      if (map['accepted_gift_types'] is! Map) {
        map['accepted_gift_types'] = Map<String, dynamic>.from(
          _newEmptyGiftSettingsWire()['accepted_gift_types']! as Map<String, dynamic>,
        );
      } else {
        final ag = map['accepted_gift_types'] is Map<String, dynamic>
            ? map['accepted_gift_types'] as Map<String, dynamic>
            : Map<String, dynamic>.from(map['accepted_gift_types'] as Map);
        map['accepted_gift_types'] = ag;
        ag['@type'] ??= 'acceptedGiftTypes';
      }
      break;
    case 'userFullInfo':
      for (final k in _kUserFullInfoOptionalObjectWireKeys) {
        final v = map[k];
        if (v is String && v.isEmpty) {
          map[k] = null;
        }
      }
      final gs = map['gift_settings'];
      if (gs is! Map) {
        map['gift_settings'] = _newEmptyGiftSettingsWire();
      } else {
        final gm = gs is Map<String, dynamic> ? gs : Map<String, dynamic>.from(gs);
        map['gift_settings'] = gm;
        gm['@type'] ??= 'giftSettings';
      }
      for (final k in [
        'gift_count',
        'group_in_common_count',
        'incoming_paid_message_star_count',
        'outgoing_paid_message_star_count',
        'pending_rating_date',
      ]) {
        if (map[k] == null) {
          map[k] = 0;
        }
      }
      break;
    case 'message':
      for (final k in [
        'id',
        'chat_id',
        'date',
        'edit_date',
        'via_bot_user_id',
        'sender_business_bot_user_id',
        'paid_message_star_count',
      ]) {
        if (map[k] == null) {
          map[k] = 0;
        }
      }
      _coerceNullableDoubleSeconds(map, 'self_destruct_in');
      _coerceNullableDoubleSeconds(map, 'auto_delete_in');
      if (map['sender_tag'] == null) {
        map['sender_tag'] = '';
      }
      if (map['author_signature'] == null) {
        map['author_signature'] = '';
      }
      if (map['summary_language_code'] == null) {
        map['summary_language_code'] = '';
      }
      break;
    case 'messagePhoto':
      for (final k in ['show_caption_above_media', 'has_spoiler', 'is_secret']) {
        if (map[k] == null) {
          map[k] = false;
        }
      }
      break;
    case 'messageAnimation':
      for (final k in ['show_caption_above_media', 'has_spoiler', 'is_secret']) {
        if (map[k] == null) {
          map[k] = false;
        }
      }
      break;
    case 'messageVideo':
      if (map['alternative_videos'] == null) {
        map['alternative_videos'] = <dynamic>[];
      }
      if (map['storyboards'] == null) {
        map['storyboards'] = <dynamic>[];
      }
      if (map['start_timestamp'] == null) {
        map['start_timestamp'] = 0;
      }
      for (final k in ['show_caption_above_media', 'has_spoiler', 'is_secret']) {
        if (map[k] == null) {
          map[k] = false;
        }
      }
      break;
    case 'userTypeBot':
      for (final k in [
        'can_be_edited',
        'can_join_groups',
        'can_read_all_group_messages',
        'has_main_web_app',
        'has_topics',
        'allows_users_to_create_topics',
        'can_manage_bots',
        'is_inline',
        'supports_guest_queries',
        'need_location',
        'can_connect_to_business',
        'can_be_added_to_attachment_menu',
      ]) {
        if (map[k] == null) {
          map[k] = false;
        }
      }
      if (map['inline_query_placeholder'] == null) {
        map['inline_query_placeholder'] = '';
      }
      if (map['active_user_count'] == null) {
        map['active_user_count'] = 0;
      }
      break;
    case 'user':
      if (map['id'] == null) {
        map['id'] = 0;
      }
      for (final k in ['first_name', 'last_name', 'phone_number', 'language_code']) {
        if (map[k] == null) {
          map[k] = '';
        }
      }
      for (final k in ['accent_color_id', 'profile_accent_color_id', 'paid_message_star_count']) {
        if (map[k] == null) {
          map[k] = 0;
        }
      }
      final tp = map['type'];
      if (tp is! Map) {
        map['type'] = <String, dynamic>{'@type': 'userTypeRegular'};
      } else {
        final tm = tp is Map<String, dynamic> ? tp : Map<String, dynamic>.from(tp);
        map['type'] = tm;
        final tName = tm['@type']?.toString();
        if (tName == null || tName.isEmpty) {
          if (tm.containsKey('has_main_web_app') ||
              tm.containsKey('can_be_edited') ||
              tm.containsKey('inline_query_placeholder')) {
            tm['@type'] = 'userTypeBot';
          } else {
            tm['@type'] = 'userTypeRegular';
          }
        }
      }
      break;
    case 'updateNewChat':
      final ch = map['chat'];
      if (ch is Map) {
        final cm = ch is Map<String, dynamic> ? ch : Map<String, dynamic>.from(ch);
        map['chat'] = cm;
        cm['@type'] ??= 'chat';
      }
      break;
    case 'updateUser':
      final u = map['user'];
      if (u is Map) {
        final um = u is Map<String, dynamic> ? u : Map<String, dynamic>.from(u);
        map['user'] = um;
        um['@type'] ??= 'user';
      }
      break;
    case 'updateUserFullInfo':
      if (map['user_id'] == null) {
        map['user_id'] = 0;
      }
      final ufi = map['user_full_info'];
      if (ufi is Map) {
        final um = ufi is Map<String, dynamic> ? ufi : Map<String, dynamic>.from(ufi);
        map['user_full_info'] = um;
        um['@type'] ??= 'userFullInfo';
      }
      break;
    default:
      break;
  }
}

void _sanitizeTdPayloadInPlace(Map<String, dynamic> map) {
  _applyTypedObjectWireFixups(map);
  for (final key in _kTdlibJsonBoolKeysNullableOnWire) {
    final v = map[key];
    if (v == null) {
      map[key] = false;
    }
  }
  for (final e in map.entries) {
    final v = e.value;
    if (v is Map<String, dynamic>) {
      _sanitizeTdPayloadInPlace(v);
    } else if (v is Map) {
      final nested = Map<String, dynamic>.from(v);
      map[e.key] = nested;
      _sanitizeTdPayloadInPlace(nested);
    } else if (v is List) {
      for (var i = 0; i < v.length; i++) {
        final item = v[i];
        if (item is Map<String, dynamic>) {
          _sanitizeTdPayloadInPlace(item);
        } else if (item is Map) {
          final nested = Map<String, dynamic>.from(item);
          v[i] = nested;
          _sanitizeTdPayloadInPlace(nested);
        }
      }
    }
  }
}

/// Parses a TDLib JSON object map, or returns null.
Map<String, dynamic>? parseTdJsonObjectMap(String raw) {
  try {
    final d = jsonDecode(raw);
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
  } catch (_) {}
  return null;
}

/// Debug aid: root `@type` (and `@extra` when present). Includes a hint for
/// `updateChatLastMessage` / reply markup (shared by native + web dispatch logs).
String tdlibJsonPeekForLog(String rawJson) {
  try {
    final d = jsonDecode(rawJson);
    if (d is! Map) {
      return 'shape=${d.runtimeType}';
    }
    final m = d is Map<String, dynamic> ? d : Map<String, dynamic>.from(d);
    final t = m['@type']?.toString() ?? 'null-@type';
    if (t == 'updateChatLastMessage') {
      final last = m['last_message'];
      if (last is Map) {
        final rm = last['reply_markup'];
        if (rm is Map) {
          return '$t reply_markup=${rm['@type']}';
        }
      }
    }
    final extra = m['@extra'];
    if (extra != null) {
      return '$t @extra=$extra';
    }
    return t;
  } catch (e) {
    return 'peek_error: $e';
  }
}

/// Normalizes TDLib **wire JSON** (primarily **tdweb**) so strict `td_api` `fromJson`
/// does not throw on null / empty-string / partial-object quirks.
///
/// **Contract:** mutates [rawJson] in place when [kIsWeb] is true; returns the same
/// map reference. When not on web, returns [rawJson] without reading the tree
/// (native TDLib JSON is treated as already spec-shaped).
///
/// Deterministic for a given input map; intended to run immediately before
/// `td.convertToObject(jsonEncode(...))`.
Map<String, dynamic> sanitizeTdPayload(Map<String, dynamic> rawJson) {
  if (!kIsWeb) {
    return rawJson;
  }
  _sanitizeTdPayloadInPlace(rawJson);
  return rawJson;
}

/// Decode → [sanitizeTdPayload] (web only) → encode for `td.convertToObject`.
///
/// On Android/desktop, returns [rawJson] unchanged (**no** extra json parse).
String tdJsonPrepareForConvertToObject(String rawJson) {
  if (!kIsWeb) {
    return rawJson;
  }
  final map = parseTdJsonObjectMap(rawJson);
  if (map == null) {
    return rawJson;
  }
  sanitizeTdPayload(map);
  try {
    return jsonEncode(map);
  } catch (_) {
    return rawJson;
  }
}
